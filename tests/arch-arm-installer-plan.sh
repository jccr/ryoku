#!/usr/bin/env bash
# Dry-runs the committed aarch64 shell installer in an Arch Linux ARM container
# and checks it takes the source lane: no [ryoku] repo, no AUR or CachyOS step,
# the build toolchain in the transaction, deploy.sh doing the build. It then
# lists the planned packages ALARM's repos lack, for the aarch64 package work.
set -euo pipefail

repo=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
image=${RYOKU_ALARM_IMAGE:-docker.io/menci/archlinuxarm:latest}
runtime=${RYOKU_CONTAINER:-$(command -v docker || command -v podman || :)}

fail() {
  printf 'arch-arm-installer-plan: FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -n $runtime ]] || fail "docker or podman is required"
[[ -x $repo/ryoku-shell-installer/ryoku-shell-install-aarch64 ]] ||
  fail "committed ryoku-shell-install-aarch64 binary is missing or not executable"

# an argument, not stdin: script(1) and pacman would read the rest of a piped harness
IFS= read -r -d '' harness <<'HARNESS' || :
set -euo pipefail

fail() {
  printf 'arch-arm-installer-plan: FAIL: %s\n' "$*" >&2
  if [ -f /tmp/installer-plan.log ]; then
    printf '%s\n' '--- dry-run log ---' >&2
    cat /tmp/installer-plan.log >&2
  fi
  exit 1
}

[ "$(uname -m)" = aarch64 ] || fail "container is $(uname -m), not aarch64"
# pacman's Landlock sandbox cannot start inside an unprivileged container
sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init > /dev/null 2>&1
pacman-key --populate archlinuxarm > /dev/null 2>&1
pacman -Syu --noconfirm --needed sudo util-linux > /dev/null 2>&1 ||
  fail "could not install sudo and util-linux in the ALARM container"
useradd -m ryoku-ci
printf '%s\n' 'ryoku-ci ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ryoku-ci
chmod 0440 /etc/sudoers.d/ryoku-ci

raw_log=/tmp/installer-plan.typescript
log=/tmp/installer-plan.log
if ! runuser -u ryoku-ci -- env \
  HOME=/home/ryoku-ci USER=ryoku-ci LOGNAME=ryoku-ci TERM=xterm-256color RYOKU_HOST_INIT=systemd \
  script -q -e -c "/repo/ryoku-shell-installer/ryoku-shell-install-aarch64 --yes --dry-run --payload /repo" "$raw_log" > /dev/null; then
  [ -f "$raw_log" ] && cat "$raw_log" >&2
  fail "the aarch64 installer dry-run failed"
fi
escape=$(printf '\033')
tr -d '\r' < "$raw_log" | sed "s/${escape}\[[0-9;]*m//g" > "$log"

for step in 'Installing Ryoku fonts and cursors' 'Building the Ryoku desktop from source' 'ryoku/shell/deploy.sh'; do
  grep -Fq "$step" "$log" || fail "source lane is missing: $step"
done
for step in 'Trusting the [ryoku] package repository' 'Building the AUR extras' 'Adding the CachyOS kernel' 'Setting up GPU drivers'; do
  ! grep -Fq "$step" "$log" || fail "source lane still runs: $step"
done
! grep -Eq 'repo\.ryoku\.dev|pacman-key --populate ryoku' "$log" ||
  fail "source lane touches the [ryoku] repository"

package_command=$(grep -E 'DRYRUN: sudo -n pacman -Syu --needed --noconfirm .* go( |$)' "$log" || :)
[ "$(printf '%s\n' "$package_command" | grep -c .)" -eq 1 ] ||
  fail "expected exactly one source-lane package transaction"
packages=" ${package_command#*--noconfirm } "
packages=$(printf '%s' "$packages" | sed 's/ --overwrite [^ ]*//')
for package in go cmake ninja qt6-shadertools quickshell hyprland; do
  case $packages in *" $package "*) ;; *) fail "transaction is missing '$package'" ;; esac
done
for package in ryoku-keyring ryoku-desktop linux-headers xpadneo-dkms ryoku-oh-my-zsh; do
  case $packages in *" $package "*) fail "transaction still names '$package'" ;; esac
done

# shellcheck disable=SC2086
missing=$({ pacman -Sp --print-format %n $packages 2>&1 || :; } | sed -n 's/^error: target not found: //p' | tr '\n' ' ')
printf 'arch-arm-installer-plan: ALARM lacks (the installer skips these): %s\n' "${missing:-none}"
printf '%s\n' 'arch-arm-installer-plan: OK'
HARNESS
if ! "$runtime" run --rm --platform linux/arm64 -v "$repo:/repo:ro" "$image" /bin/bash -c "$harness"; then
  fail "ALARM container installer-plan check failed"
fi
