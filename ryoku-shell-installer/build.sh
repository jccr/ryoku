#!/usr/bin/env bash
# Builds the committed shell-installer binaries and their checksums. The
# toolchain comes from go.mod and the build is static and path-free, so any
# host produces the same bytes and CI can rebuild a binary and diff it.
#
#   build.sh                 the aarch64 binary
#   build.sh x86_64 aarch64  both
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GOTOOLCHAIN="go$(awk '$1 == "go" { print $2; exit }' go.mod)"
export GOTOOLCHAIN CGO_ENABLED=0 GOOS=linux GOFLAGS=-buildvcs=false

sum() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}

[[ $# -gt 0 ]] || set -- aarch64
for machine in "$@"; do
  case $machine in
    x86_64) goarch=amd64 bin=ryoku-shell-install ;;
    aarch64) goarch=arm64 bin=ryoku-shell-install-aarch64 ;;
    *) printf 'build.sh: unknown machine %s (x86_64 or aarch64)\n' "$machine" >&2; exit 2 ;;
  esac
  GOARCH=$goarch go build -trimpath -ldflags='-s -w' -o "$bin" .
  sum "$bin" > "$bin.sha256"
  printf '%s\n' "$(cat "$bin.sha256")"
done
