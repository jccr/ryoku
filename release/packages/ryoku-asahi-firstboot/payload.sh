#!/bin/sh
# The first-boot setup of a Mac, shared by the Fedora Asahi Remix extra and the
# Arch Linux ARM image: the preinstalled wizard, its backend and service, the
# shell installer, and the backend libraries the setup sources.
set -eu

: "${RYOKU_SRC:?RYOKU_SRC is required}"
: "${RYOKU_BUILD_DIR:?RYOKU_BUILD_DIR is required}"

usage() {
	printf 'usage: payload.sh build | install DESTDIR systemd fedora|arch\n' >&2
	exit 2
}

# The channel this package was built for picks the branch the first boot
# installs the desktop from, so the setup and the desktop come from one channel.
ref() {
	case ${RYOKU_CHANNEL:-} in
	testing) printf 'aarch64-phase4a\n' ;;
	*) printf 'main\n' ;;
	esac
}

case "${1:-}" in
build)
	mkdir -p "$RYOKU_BUILD_DIR"
	cd "$RYOKU_SRC/installation/tui"
	CGO_ENABLED=0 go build -trimpath -o "$RYOKU_BUILD_DIR/ryoku-tui" .
	;;
install)
	destdir=${2:-}
	init=${3:-}
	edition=${4:-}
	[ -n "$destdir" ] || usage
	[ "$init" = systemd ] || { printf 'payload.sh: the first boot needs systemd, not %s\n' "$init" >&2; exit 2; }
	case "$edition" in
	fedora) variant='asahi' ;;
	arch) variant='asahi-alarm' ;;
	*) usage ;;
	esac
	asahi="$RYOKU_SRC/installation/asahi"
	libexec="$destdir/usr/libexec/ryoku-asahi"
	install -Dm755 "$RYOKU_BUILD_DIR/ryoku-tui" "$libexec/ryoku-tui"
	install -Dm755 "$RYOKU_SRC/ryoku-shell-installer/ryoku-shell-install-aarch64" "$libexec/ryoku-shell-install"
	install -Dm755 "$asahi/ryoku-firstboot-session" "$libexec/ryoku-firstboot-session"
	install -Dm755 "$asahi/ryoku-firstboot-install" "$libexec/ryoku-firstboot-install"
	install -Dm644 "$asahi/ryoku-firstboot.service" "$destdir/usr/lib/systemd/system/ryoku-firstboot.service"
	install -d "$destdir/usr/share/ryoku-asahi" "$destdir/usr/share/ryoku"
	ref > "$destdir/usr/share/ryoku-asahi/ref"
	printf '%s\n' "$variant" > "$destdir/usr/share/ryoku/variant"
	# Arch's choices are the shared catalogue itself; Fedora's come from its table.
	if [ "$edition" = fedora ]; then
		install -Dm644 "$RYOKU_SRC/fedora/packages/translations.tsv" "$destdir/usr/share/ryoku/fedora/packages/translations.tsv"
	fi
	for lib in common.sh i18n.sh accounts.sh chroot.sh; do
		install -Dm644 "$RYOKU_SRC/installation/backend/lib/$lib" "$destdir/usr/share/ryoku/installation/backend/lib/$lib"
	done
	;;
*)
	usage
	;;
esac
