#!/usr/bin/env bash
# Builds Ryoku's Fedora RPMs on aarch64 the way the publish workflow's build
# job does, unsigned (RYOKU_RPM_LOCAL=1), in an arm64 fedora container. Every
# spec builds on its own, so one failure does not hide the next; one that
# rpmbuild refuses for this architecture is reported as x86-only. results.tsv
# lists each spec's outcome and logs/ holds each build log. When nothing failed,
# build-rpm-repo.sh, which skips the x86-only specs itself, assembles a local
# repository in <out>/repo for `dnf --repofrompath`.
#
#   tests/fedora-arm-rpm-build.sh <out-dir>
set -euo pipefail

repo=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
release=${RYOKU_FEDORA_RELEASE:-44}
image=${RYOKU_FEDORA_IMAGE:-docker.io/library/fedora:$release}
runtime=${RYOKU_CONTAINER:-$(command -v docker || command -v podman || :)}
cache=${RYOKU_FEDORA_ARM_CACHE:-ryoku-fedora-$release-aarch64-cache}

fail() {
  printf 'fedora-arm-rpm-build: FAIL: %s\n' "$*" >&2
  exit 1
}

(($# == 1)) || fail "usage: $0 <out-dir>"
[[ -n $runtime ]] || fail "docker or podman is required"
out=$1
[[ ! -e $out ]] || fail "output already exists: $out"
mkdir -p "$out"
out=$(cd "$out" && pwd)
[[ $out != "$repo" && $out != "$repo"/* ]] || fail "keep the output outside the checkout: $out"

IFS= read -r -d '' harness <<'HARNESS' || :
set -euo pipefail

fail() {
  printf 'fedora-arm-rpm-build: FAIL: %s\n' "$*" >&2
  exit 1
}

arch=$(uname -m)
[ "$arch" = aarch64 ] || fail "container is $arch, not aarch64"
dnf install -y git tar gzip curl jq ccache dnf-plugins-core dnf5-plugins \
  rpm-build rpm-sign createrepo_c gnupg2 > /out/logs/setup.log 2>&1 ||
  fail "could not install the build tools (see logs/setup.log)"
git config --global --add safe.directory /repo

# the build job's restricted COPR repositories, rendered the same way
while IFS=$'\t' read -r copr packages _ || [[ -n $copr ]]; do
  [[ -n $copr && $copr != \#* && $copr != copr ]] || continue
  owner=${copr%%/*}
  project=${copr#*/}
  cat > "/etc/yum.repos.d/ryoku-build-copr-$owner-$project.repo" <<EOF
[ryoku-build-copr-$owner-$project]
name=Ryoku build dependency: $owner/$project
baseurl=https://download.copr.fedorainfracloud.org/results/$owner/$project/fedora-\$releasever-\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://download.copr.fedorainfracloud.org/results/$owner/$project/pubkey.gpg
includepkgs=$packages
skip_if_unavailable=1
EOF
done < /repo/fedora/packages/build-coprs.tsv

results=/out/results.tsv
printf 'spec\tresult\tdetail\n' > "$results"
declare -A outcome=()
# every spec, x86-only ones too: prepare-srpms.sh fetches all their sources,
# and fetch hooks need their spec's build tools (npm, pnpm)
for spec in /repo/fedora/packages/rpm/*.spec; do
  name=$(basename "$spec" .spec)
  if ! dnf builddep -y "$spec" > "/out/logs/$name.builddep.log" 2>&1; then
    outcome[$name]=builddep-failed
    printf '%s\tbuilddep-failed\tlogs/%s.builddep.log\n' "$name" "$name" >> "$results"
  fi
done

RYOKU_RPM_LOCAL=1 RYOKU_SRPM_OUT=/out/srpms-all \
  /repo/fedora/packages/rpm/prepare-srpms.sh > /out/logs/prepare-srpms.log 2>&1 ||
  fail "prepare-srpms.sh failed (see logs/prepare-srpms.log)"

export CCACHE_DIR=/cache/ccache CCACHE_MAXSIZE=2G GOCACHE=/cache/go GOMODCACHE=/cache/gomod
export PATH=/usr/lib64/ccache:$PATH
mkdir -p /out/rpms "$CCACHE_DIR" "$GOCACHE" "$GOMODCACHE"
failed=0
for srpm in /out/srpms-all/*.src.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$srpm")
  if [[ ${outcome[$name]:-} == builddep-failed ]]; then
    failed=1
    continue
  fi
  started=$SECONDS
  if rpmbuild --define "_buildhost ryoku-builder" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "_topdir /root/rpmbuild" --define "_rpmdir /out/rpms" \
    --rebuild "$srpm" > "/out/logs/$name.build.log" 2>&1; then
    printf '%s\tbuilt\t%ss\n' "$name" "$((SECONDS - started))" >> "$results"
  elif grep -q '^error: Architecture is not included' "/out/logs/$name.build.log"; then
    printf '%s\tx86-only\tnot built for %s\n' "$name" "$arch" >> "$results"
  else
    failed=1
    printf '%s\tbuild-failed\tlogs/%s.build.log\n' "$name" "$name" >> "$results"
  fi
  printf 'fedora-arm-rpm-build: %s\n' "$(tail -n1 "$results" | tr '\t' ' ')"
done

cat "$results"
((failed == 0)) || fail "some specs did not build on $arch; see results.tsv"
RYOKU_RPM_LOCAL=1 RYOKU_SRPM_IN=/out/srpms-all RYOKU_RPM_OUT=/out/repo \
  /repo/fedora/packages/rpm/build-rpm-repo.sh > /out/logs/build-rpm-repo.log 2>&1 ||
  fail "build-rpm-repo.sh failed (see logs/build-rpm-repo.log)"
printf '%s\n' 'fedora-arm-rpm-build: OK, local repository in repo/'
HARNESS

mkdir -p "$out/logs"
"$runtime" run --rm --platform linux/arm64 \
  -v "$repo:/repo:ro" -v "$out:/out" -v "$cache:/cache" \
  "$image" /bin/bash -c "$harness" ||
  fail "aarch64 RPM build failed; results in $out/results.tsv"
