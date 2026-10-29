#!/usr/bin/env bash
# Stages the Asahi first-boot payload for both editions and dry-runs the staged
# backend, checking the system changes it would make, in order. A library the
# payload fails to stage fails the dry-run that sources it.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
payload=$repo/release/packages/ryoku-asahi-firstboot/payload.sh

fail() {
  printf 'asahi first-boot dry-run: %s\n' "$*" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/build"
: >"$tmp/build/ryoku-tui"
# shellcheck disable=SC2016  # a literal sha512-crypt prefix
hash='$6$saltsalt$'$(printf 'a%.0s' {1..86})

for edition in fedora arch; do
  RYOKU_SRC="$repo" RYOKU_BUILD_DIR="$tmp/build" RYOKU_CHANNEL=testing RYOKU_REF=unstable-dev \
    "$payload" install "$tmp/$edition" systemd "$edition" || fail "payload did not stage the $edition edition"
done

# dryrun <edition> [VAR=value...]: the staged backend of that edition.
dryrun() {
  local stage=$tmp/$1
  shift
  env -i PATH="$PATH" HOME="$tmp" \
  RYOKU_DRYRUN=1 RYOKU_VARIANT="$(cat "$stage/usr/share/ryoku/variant")" \
  RYOKU_ASAHI_SHARE="$stage/usr/share/ryoku-asahi" \
  RYOKU_BACKEND_LIB="$stage/usr/share/ryoku/installation/backend/lib" \
  RYOKU_FIRSTBOOT_STATE="$tmp/state-none" \
  RYOKU_KEYMAP=de RYOKU_XKB_LAYOUT=de RYOKU_XKB_VARIANT=nodeadkeys \
  RYOKU_LOCALE=de_DE.UTF-8 RYOKU_TIMEZONE=Europe/Berlin RYOKU_HOSTNAME=mac \
  RYOKU_USERNAME=ada RYOKU_FULLNAME='Ada L' RYOKU_PASSWORD_HASH="$hash" \
  RYOKU_COMPOSITOR=hyprland RYOKU_BROWSER=firefox RYOKU_LOGIN_SHELL=fish \
  RYOKU_FILE_MANAGER=nautilus RYOKU_RASHIN=0 RYOKU_WITHOUT=voxtype,ryotunes \
  "$@" bash "$stage/usr/libexec/ryoku-asahi/ryoku-firstboot-install"
}

# expect_in_order <output> <line>...: every line appears, in this order.
expect_in_order() {
  local out=$1 rest=$1 line
  shift
  for line in "$@"; do
    [[ $rest == *"$line"* ]] || fail "missing, or out of order: $line
$out"
    rest=${rest#*"$line"}
  done
}

desktop=(
  '@@RYOKU_STEP desktop'
  'DRYRUN: write /etc/sudoers.d/90-ryoku-firstboot:'
  'DRYRUN: loginctl enable-linger ada'
  'DRYRUN: systemctl start user@1000.service'
  '/usr/libexec/ryoku-asahi/ryoku-shell-install --yes --ref unstable-dev --compositor hyprland --browser firefox --shell fish --file-manager nautilus --rashin=false --without voxtype,ryotunes'
  '@@RYOKU_STEP finish'
  'DRYRUN: loginctl disable-linger ada'
  'DRYRUN: rm -f /etc/sudoers.d/90-ryoku-firstboot'
  'DRYRUN: systemctl disable ryoku-firstboot.service'
  '@@RYOKU_DONE'
)

out=$(dryrun fedora) || fail "Fedora backend exited non-zero:
$out"

expect=(
  '@@RYOKU_STEP system'
  'DRYRUN: localectl set-keymap de'
  'DRYRUN: localectl set-x11-keymap de  nodeadkeys'
  'DRYRUN: dnf -y install glibc-langpack-de'
  'DRYRUN: timedatectl set-timezone Europe/Berlin'
  'DRYRUN: hostnamectl set-hostname mac'
  '@@RYOKU_STEP accounts'
  'DRYRUN: dnf -y install fish'
  'DRYRUN: btrfs subvolume create /home/ada'
  'DRYRUN: chroot / useradd -M -U -d /home/ada -s /usr/bin/fish -G wheel,input,video -c Ada L ada'
  'DRYRUN: chroot / passwd -l root'
  "${desktop[@]}"
)
expect_in_order "$out" "${expect[@]}"

out=$(dryrun arch) || fail "Arch backend exited non-zero:
$out"
expect=(
  '@@RYOKU_STEP system'
  'DRYRUN: localectl set-keymap de'
  'DRYRUN: sed -i s|^#\(de_DE\.UTF-8 \)|\1| /etc/locale.gen'
  'DRYRUN: write /etc/locale.conf:'
  'DRYRUN: chroot / locale-gen'
  'DRYRUN: timedatectl set-timezone Europe/Berlin'
  '@@RYOKU_STEP accounts'
  'DRYRUN: pacman -S --needed --noconfirm fish'
  'DRYRUN: chroot / useradd -M -U -d /home/ada -s /usr/bin/fish -G wheel,input,video -c Ada L ada'
  "${desktop[@]}"
)
expect_in_order "$out" "${expect[@]}"
[[ $out != *dnf* ]] || fail "the Arch first boot calls dnf:
$out"

# A retry after a later step failed keeps the accounts the first run made and
# gives its administrator the password just entered.
mkdir -p "$tmp/state"
printf 'ada\n' >"$tmp/state/accounts"
out=$(dryrun arch RYOKU_FIRSTBOOT_STATE="$tmp/state" RYOKU_USERNAME=grace) \
  || fail "the retried backend exited non-zero:
$out"
expect_in_order "$out" \
  '@@RYOKU_STEP accounts' \
  'accounts: kept from the earlier run (administrator ada)' \
  'DRYRUN: chpasswd -e (ada:hash via stdin)' \
  "${desktop[@]}"
[[ $out != *useradd* && $out != *'subvolume create'* ]] || fail "the retry creates the accounts again:
$out"
printf 'asahi first-boot dry-run: ok\n'
