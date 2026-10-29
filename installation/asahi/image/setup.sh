#!/usr/bin/env bash
# setup.sh: turns the Arch Linux ARM root into a Mac system, inside the image
# root (build.sh runs it through arch-chroot). It follows asahi-alarm-builder's
# base scripts (MIT, github.com/asahi-alarm/asahi-alarm-builder): the
# asahi-alarm repository, the Asahi kernel and boot chain, and GRUB on a btrfs
# root. Then it removes the stock alarm account and hands tty1 to Ryoku's
# first-boot wizard, which creates the real accounts.
#
#   ROOT_UUID, EFI_UUID   the filesystem IDs build.sh formats the image with
#   /tmp/ryoku-image/     this script and the ryoku-asahi-firstboot package
set -euo pipefail

: "${ROOT_UUID:?}" "${EFI_UUID:?}"
files=/tmp/ryoku-image
asahi_alarm_key=12CE6799A94A3F1B5DDFFE88F576553597FB8FEB

pacman_repos() {
  sed -i -e 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
  # A container cannot start pacman's Landlock sandbox; the image's own
  # pacman.conf gets it back before the image is packed.
  sed -i -e '/^\[options\]/a DisableSandbox' /etc/pacman.conf
  sed -i -e '/^\[core\]/i [asahi-alarm]\nInclude = /etc/pacman.d/mirrorlist.asahi-alarm\n' /etc/pacman.conf
  # shellcheck disable=SC2016  # $arch is pacman's, not the shell's
  printf 'Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/$arch\n' \
    >/etc/pacman.d/mirrorlist.asahi-alarm
  # pacman.conf runs downloads as alpm, which sysusers declares.
  systemd-sysusers
  pacman-key --init
  pacman-key --populate archlinuxarm
  pacman-key --recv-keys "$asahi_alarm_key"
  pacman-key --lsign-key "$asahi_alarm_key"
}

# update-m1n1 writes the boot object to /boot/efi/m1n1 when .builder marks a
# build root; build.sh copies that directory to the EFI partition.
kernel_and_boot() {
  install -d /boot/efi/EFI/BOOT /boot/efi/m1n1
  touch /boot/efi/.builder
  pacman --noconfirm -R linux-aarch64
  pacman --noconfirm -Syu
  pacman --noconfirm -S --needed asahi-alarm-keyring asahi-scripts asahi-fwextract \
    m1n1 uboot-asahi mkinitcpio grub sudo networkmanager btrfs-progs
  sed -i -e 's/^HOOKS=(base.*/HOOKS=(base asahi udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' \
    -e 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
  pacman --noconfirm -S linux-asahi asahi-meta
}

filesystems() {
  local opts=rw,relatime,x-systemd.growfs,compress=zstd:1
  cat >/etc/fstab <<EOF
UUID=$ROOT_UUID / btrfs $opts,subvol=@ 0 0
UUID=$ROOT_UUID /home btrfs $opts,subvol=@home 0 0
UUID=$EFI_UUID /boot/efi vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
EOF
}

# GRUB is a standalone EFI image with the root's UUID and the @ prefix baked
# in; build.sh copies it to the EFI partition and runs grub-mkconfig on the
# packed root.
grub_image() {
  cat >/tmp/grub-core.cfg <<EOF
search.fs_uuid $ROOT_UUID root
set prefix=(\$root)'/@/boot/grub'
EOF
  sed -i '/efi_uga/d' /etc/grub.d/00_header
  rm -f /etc/grub.d/30_uefi-firmware
  install -d /boot/grub/fonts /boot/grub/locale
  touch /boot/grub/device.map
  dd if=/dev/zero of=/boot/grub/grubenv bs=1024 count=1 status=none
  cp -r /usr/share/grub/themes /boot/grub/
  cp -r /usr/lib/grub/arm64-efi /boot/grub/
  rm -f /boot/grub/arm64-efi/*.module
  cp /usr/share/grub/unicode.pf2 /boot/grub/fonts/
  local mo lc
  for mo in /usr/share/locale/*/LC_MESSAGES/grub.mo; do
    lc=${mo#/usr/share/locale/}
    cp "$mo" "/boot/grub/locale/${lc%%/*}.mo"
  done
  grub-mkimage --directory /usr/lib/grub/arm64-efi -c /tmp/grub-core.cfg \
    --prefix /boot/grub --output /boot/grub/arm64-efi/core.efi \
    --format arm64-efi --compression auto ext2 part_gpt search btrfs
}

# The tarball's alarm/alarm and root/root logins would be open on every Mac.
# Root stays locked unless the wizard sets a password; wheel gets sudo, as the
# ISO install configures it.
accounts() {
  userdel -r alarm
  passwd -l root
  printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/10-wheel
  chmod 0440 /etc/sudoers.d/10-wheel
}

ryoku_firstboot() {
  pacman --noconfirm -U "$files"/ryoku-asahi-firstboot-*.pkg.tar.*
  # systemd-firstboot would prompt on the console the wizard owns; with no
  # prompt it only seeds a machine ID.
  install -d /etc/systemd/system/systemd-firstboot.service.d
  printf '[Service]\nExecStart=\nExecStart=systemd-firstboot\n' \
    >/etc/systemd/system/systemd-firstboot.service.d/no-prompt.conf
  systemctl enable NetworkManager.service ryoku-firstboot.service
  systemctl set-default multi-user.target
}

pacman_repos
kernel_and_boot
filesystems
grub_image
accounts
ryoku_firstboot
sed -i -e '/^DisableSandbox$/d' /etc/pacman.conf
rm -f /var/cache/pacman/pkg/*
