#!/usr/bin/env bash
# Vets and tests the shell installer. It compiles for Linux only, so any other
# host runs it in a Go container; the checkout is mounted read-only because a
# plain `go build ./...` there overwrites the committed binary. Arguments pass
# through to `go test` (e.g. -run TestStepsPerDistro).
set -euo pipefail

repo=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
version=$(awk '$1 == "go" { print $2; exit }' "$repo/ryoku-shell-installer/go.mod")
gates="go vet ./... && go test -count=1 ./...$(printf ' %q' "$@")"

if [[ $(uname -s) == Linux ]] && command -v go > /dev/null 2>&1; then
  cd "$repo/ryoku-shell-installer"
  GOTOOLCHAIN="go$version" bash -c "$gates"
  exit
fi

runtime=${RYOKU_CONTAINER:-$(command -v podman || command -v docker || :)}
[[ -n $runtime ]] || { printf 'installer-unit: FAIL: needs Linux with go, or podman/docker\n' >&2; exit 1; }
"$runtime" run --rm \
  -v "$repo:/src:ro" -v ryoku-gocache:/root/.cache -v ryoku-gomod:/go/pkg \
  -w /src/ryoku-shell-installer -e GOFLAGS=-buildvcs=false \
  "docker.io/library/golang:$version" bash -c "$gates"
