#!/usr/bin/env bash
# Dry-runs the Asahi first-boot backend and checks the system changes it would
# make, in order, plus that its RPM payload stages every library it sources.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
backend=$repo/installation/asahi/ryoku-firstboot-install
payload=$repo/release/packages/ryoku-asahi-firstboot/payload.sh

fail() {
  printf 'asahi first-boot dry-run: %s\n' "$*" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'unstable-dev\n' >"$tmp/ref"
# shellcheck disable=SC2016  # a literal sha512-crypt prefix
hash='$6$saltsalt$'$(printf 'a%.0s' {1..86})

out=$(env -i PATH="$PATH" HOME="$tmp" \
  RYOKU_DRYRUN=1 \
  RYOKU_ASAHI_SHARE="$tmp" \
  RYOKU_BACKEND_LIB="$repo/installation/backend/lib" \
  RYOKU_KEYMAP=de RYOKU_XKB_LAYOUT=de RYOKU_XKB_VARIANT=nodeadkeys \
  RYOKU_LOCALE=de_DE.UTF-8 RYOKU_TIMEZONE=Europe/Berlin RYOKU_HOSTNAME=mac \
  RYOKU_USERNAME=ada RYOKU_FULLNAME='Ada L' RYOKU_PASSWORD_HASH="$hash" \
  RYOKU_COMPOSITOR=hyprland RYOKU_BROWSER=firefox RYOKU_LOGIN_SHELL=fish \
  RYOKU_FILE_MANAGER=nautilus RYOKU_RASHIN=0 RYOKU_WITHOUT=voxtype,ryotunes \
  bash "$backend") || fail "backend exited non-zero:
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
  '@@RYOKU_STEP desktop'
  'DRYRUN: write /etc/sudoers.d/90-ryoku-firstboot:'
  'DRYRUN: loginctl enable-linger ada'
  '/usr/libexec/ryoku-asahi/ryoku-shell-install --yes --ref unstable-dev --compositor hyprland --browser firefox --shell fish --file-manager nautilus --rashin=false --without voxtype,ryotunes'
  '@@RYOKU_STEP finish'
  'DRYRUN: loginctl disable-linger ada'
  'DRYRUN: rm -f /etc/sudoers.d/90-ryoku-firstboot'
  'DRYRUN: systemctl disable ryoku-firstboot.service'
  '@@RYOKU_DONE'
)
rest=$out
for line in "${expect[@]}"; do
  [[ $rest == *"$line"* ]] || fail "missing, or out of order: $line
$out"
  rest=${rest#*"$line"}
done

# Every library the backend and its libraries source must be in the package.
for lib in $(grep -ho 'RYOKU_BACKEND_LIB/[a-z0-9_-]*\.sh' "$backend" | sed 's|.*/||') i18n.sh; do
  grep -Eq "for lib in .*\\b$lib\\b" "$payload" || fail "payload does not stage $lib"
done
printf 'asahi first-boot dry-run: ok\n'
