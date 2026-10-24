#!/usr/bin/env bash
#
# ryoku-shell bootstrap: fetch and run the standalone Ryoku desktop installer
# on an existing supported machine. Kept deliberately dumb: every real decision
# lives in the ryoku-shell-install binary this script downloads.
#
#   curl -fsSL https://raw.githubusercontent.com/jccr/ryoku/main/ryoku-shell-installer/install.sh | bash
#
# args after `bash -s --` are forwarded to the installer (--yes, --dry-run).
# RYOKU_SHELL_REF picks the git ref to fetch the installer and payload from.
# unstable-dev also puts the box on the unstable (testing) package channel:
#
#   curl -fsSL https://raw.githubusercontent.com/jccr/ryoku/unstable-dev/ryoku-shell-installer/install.sh | RYOKU_SHELL_REF=unstable-dev bash
set -euo pipefail

main() {
  local ref="${RYOKU_SHELL_REF:-main}"
  local raw="https://raw.githubusercontent.com/jccr/ryoku/${ref}/ryoku-shell-installer"

  # English on purpose: this bootstrap runs before any Ryoku catalog exists on
  # the box to translate from; the ryoku-shell-install binary it fetches does that.
  say() { printf '\033[38;2;242;86;35m==>\033[0m %s\n' "$*"; }
  die() {
    printf 'ryoku-shell: %s\n' "$*" >&2
    exit 1
  }

  [[ $(id -u) -ne 0 ]] || die "run as your normal user, not root (sudo is used when needed)"

  # NixOS needs a nix-based engine; that work is parked (archived flake),
  # so refuse honestly instead of dying on the package-manager guard below.
  [[ ! -e /etc/NIXOS ]] || die "NixOS is not supported yet; use the flake instead"

  local ryoku_family dnf_cmd bin
  if command -v pacman > /dev/null 2>&1; then
    ryoku_family=arch
  elif command -v apt-get > /dev/null 2>&1; then
    ryoku_family=debian
  elif command -v xbps-install > /dev/null 2>&1; then
    ryoku_family=void
  elif command -v dnf5 > /dev/null 2>&1 || command -v dnf > /dev/null 2>&1; then
    ryoku_family=fedora
    if command -v dnf5 > /dev/null 2>&1; then
      dnf_cmd=dnf5
    else
      dnf_cmd=dnf
    fi
  else
    die "unsupported distribution: Ryoku installs on Arch-based, Debian-based, Void and Fedora systems"
  fi
  case "$(uname -m)" in
    x86_64) bin=ryoku-shell-install ;;
    aarch64)
      [[ $ryoku_family == arch || $ryoku_family == fedora ]] || die "off x86_64, Ryoku installs on Arch-based and Fedora systems only for now"
      bin=ryoku-shell-install-aarch64
      ;;
    *) die "Ryoku ships x86_64 and aarch64 builds only" ;;
  esac
  if [[ $ryoku_family == fedora && -e /run/ostree-booted ]]; then
    die "rpm-ostree systems are not supported; use a mutable Fedora Workstation or Server install"
  fi
  if [[ ! -d /run/systemd/system && $ryoku_family != void ]]; then
    die "this installer needs systemd on Arch, Debian and Fedora; Void uses runit"
  fi
  if [[ $ryoku_family == void ]] && { ! command -v curl > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; }; then
    say "installing bootstrap tools (curl, git)"
    sudo xbps-install -Sy curl git
  elif [[ $ryoku_family == fedora ]] && { ! command -v curl > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; }; then
    say "installing bootstrap tools (curl, git)"
    sudo "$dnf_cmd" install -y curl git
  fi
  command -v curl > /dev/null 2>&1 || die "curl is required"

  # warn-only on derivatives: the package manager is what actually matters.
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-} ${ID_LIKE:-}" in
      *arch*|*debian*|*void*|*fedora*) ;;
      *) say "warning: ${PRETTY_NAME:-unknown distro} is not recognised; continuing as ${ryoku_family}" ;;
    esac
  fi
  if [[ $ryoku_family == debian ]]; then
    say "Debian detected: the desktop is built from source, which takes a few minutes"
  elif [[ $bin == ryoku-shell-install-aarch64 ]]; then
    say "aarch64 detected: the desktop is built from source, which takes a few minutes"
  fi

  # global, not local: the EXIT trap fires after main returns, when a local is
  # gone and set -u would turn every finished run into exit 1.
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT

  say "// fetching  Ryoku shell installer (${ref})"
  curl -fsSL --retry 3 -o "$work/$bin" "$raw/$bin"
  curl -fsSL --retry 3 -o "$work/$bin.sha256" "$raw/$bin.sha256"
  (cd "$work" && sha256sum --check --quiet "$bin.sha256") \
    || die "checksum mismatch on the downloaded installer; try again"
  chmod +x "$work/$bin"

  say "// starting  Ryoku shell installer"
  local rc=0
  # piped stdin (curl | bash) is useless to a TUI; hand it the real terminal.
  if [[ ! -t 0 && -r /dev/tty ]]; then
    RYOKU_SHELL_REF="$ref" "$work/$bin" "$@" < /dev/tty || rc=$?
  else
    RYOKU_SHELL_REF="$ref" "$work/$bin" "$@" || rc=$?
  fi
  return "$rc"
}

main "$@"
