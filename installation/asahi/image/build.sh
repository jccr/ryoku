#!/usr/bin/env bash
# build.sh: builds Ryoku's Arch Linux ARM image for the Asahi installer.
#
#   build.sh <ryoku-asahi-firstboot package> <out dir>
#
# The signed Arch Linux ARM tarball becomes a btrfs root (@ and @home) with the
# Asahi kernel and boot chain and Ryoku's first-boot wizard (setup.sh). The
# result is what the Asahi installer lays down: <name>.zip holding esp/ and
# root.img, plus <name>.json with the sizes and IDs installer-data writes into
# the OS list, and <name>.zip.sha256.
#
# Runs as root on Arch Linux ARM with arch-install-scripts, btrfs-progs, gnupg,
# rsync and zip, and needs loop devices (a privileged container).
set -euo pipefail

package=$(realpath "${1:?ryoku-asahi-firstboot package}")
out=$(realpath -m "${2:?out dir}")
here=$(cd "$(dirname "$0")" && pwd)
work=${RYOKU_IMAGE_WORK:-/var/tmp/ryoku-asahi-image}
tarball_url=${RYOKU_ALARM_TARBALL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
# Arch Linux ARM Build System <builder@archlinuxarm.org>
alarm_key=68B3537F39A313B3E574D06777193F152BDBE6A6

root=$work/root
stage=$work/stage
mnt=$work/mnt
name=ryoku-alarm-$(date -u +%Y%m%d%H%M)
loop=

log() { printf '## %s\n' "$*"; }

cleanup() {
  local m
  for m in "$mnt/home" "$mnt" "$root"; do
    mountpoint -q "$m" && umount -R "$m"
  done
  [[ -z $loop ]] || losetup -d "$loop"
}
trap cleanup EXIT

# The tarball comes over plain HTTP from the mirror network, so only its
# signature by the Arch Linux ARM build key vouches for it.
fetch_tarball() {
  local tarball=$work/${tarball_url##*/} gnupg
  log "downloading $tarball_url"
  curl -fL --retry 3 -o "$tarball" -z "$tarball" "$tarball_url"
  curl -fL --retry 3 -o "$tarball.sig" "$tarball_url.sig"
  gnupg=$(mktemp -d)
  gpg --homedir "$gnupg" --quiet --import /usr/share/pacman/keyrings/archlinuxarm.gpg
  gpg --homedir "$gnupg" --status-fd 1 --verify "$tarball.sig" "$tarball" 2>/dev/null \
    | grep -q "^\[GNUPG:\] VALIDSIG .* $alarm_key\$" \
    || { echo "the Arch Linux ARM tarball is not signed by $alarm_key" >&2; exit 1; }
  rm -rf "$gnupg"
  log "tarball $(sha256sum "$tarball" | cut -d' ' -f1)"
  TARBALL=$tarball
}

# Each image gets its own filesystem IDs, so two Ryoku installs on one Mac
# never answer GRUB's search for the other's root.
new_ids() {
  local efi
  ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
  efi=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')
  EFI_VOLUME_ID=0x$efi
  efi=${efi^^}
  EFI_UUID=${efi:0:4}-${efi:4:4}
  export ROOT_UUID EFI_UUID
}

prepare_root() {
  log 'unpacking the root'
  rm -rf "$root"
  mkdir -p "$root"
  bsdtar -xpf "$TARBALL" -C "$root"
  mount --bind "$root" "$root"
  # arch-chroot mounts a fresh tmpfs on /tmp, so the inputs wait in /var/tmp.
  install -d "$root/var/tmp/ryoku-image"
  install -m755 "$here/setup.sh" "$root/var/tmp/ryoku-image/setup.sh"
  install -m644 "$package" "$root/var/tmp/ryoku-image/"
  log 'setting up the root'
  arch-chroot "$root" /var/tmp/ryoku-image/setup.sh
  rm -rf "$root/var/tmp/ryoku-image"
}

pack_root() {
  local size
  size=$(du -s -B M "$root" | cut -dM -f1)
  size=$((size + size / 8 + 256))
  log "root image: $size MiB"
  rm -rf "$stage"
  mkdir -p "$stage" "$mnt"
  truncate -s "${size}M" "$stage/root.img"
  mkfs.btrfs -q -U "$ROOT_UUID" -L ryoku-root "$stage/root.img"
  loop=$(losetup --find --show "$stage/root.img")
  mount -o subvolid=5 "$loop" "$mnt"
  btrfs -q subvolume create "$mnt/@"
  btrfs -q subvolume create "$mnt/@home"
  umount "$mnt"
  mount -o subvol=@,compress=zstd:1 "$loop" "$mnt"
  mkdir -p "$mnt/home"
  mount -o subvol=@home,compress=zstd:1 "$loop" "$mnt/home"
  rsync -aHAX --exclude '/tmp/*' --exclude /etc/machine-id --exclude '/boot/efi/*' "$root/" "$mnt/"
  arch-chroot "$mnt" grub-mkconfig -o /boot/grub/grub.cfg
  umount "$mnt/home" "$mnt"
  losetup -d "$loop"
  loop=
  ROOT_BYTES=$(stat -c %s "$stage/root.img")
}

pack_esp() {
  install -d "$stage/esp/EFI/BOOT"
  install -m644 "$root/boot/grub/arm64-efi/core.efi" "$stage/esp/EFI/BOOT/BOOTAA64.EFI"
  cp -r "$root/boot/efi/m1n1" "$stage/esp/"
}

write_zip() {
  mkdir -p "$out"
  log "compressing $name.zip"
  rm -f "$out/$name.zip"
  (cd "$stage" && zip -q -1 -r "$out/$name.zip" esp root.img)
  (cd "$out" && sha256sum "$name.zip" >"$name.zip.sha256")
  jq -n --arg package "$name.zip" --argjson root_bytes "$ROOT_BYTES" \
    --arg efi_volume_id "$EFI_VOLUME_ID" \
    '{package: $package, root_bytes: $root_bytes, efi_volume_id: $efi_volume_id}' \
    >"$out/$name.json"
  rm -rf "$stage"
}

mkdir -p "$work"
fetch_tarball
new_ids
prepare_root
umount -R "$root"
pack_root
pack_esp
write_zip
log "done: $out/$name.zip"
