# shellcheck shell=bash
startdir=${startdir:?stage-package.sh must set startdir}
srcdir=${srcdir:?stage-package.sh must set srcdir}
pkgdir=${pkgdir:?stage-package.sh must set pkgdir}
_repo="$startdir/../../../.."
_asahi="$_repo/installation/asahi"
_lib="$_repo/installation/backend/lib"

build() {
  (cd "$_repo/installation/tui" && go build -o "$srcdir/ryoku-tui" .)
}

# The channel this package was built for picks the branch the first boot
# installs the desktop from, so the setup and the desktop come from one channel.
_ref() {
  case ${RYOKU_CHANNEL:-} in
    testing) printf 'unstable-dev\n' ;;
    *) printf 'main\n' ;;
  esac
}

package() {
  local libexec="$pkgdir/usr/libexec/ryoku-asahi"
  install -Dm755 "$srcdir/ryoku-tui" "$libexec/ryoku-tui"
  install -Dm755 "$_repo/ryoku-shell-installer/ryoku-shell-install-aarch64" "$libexec/ryoku-shell-install"
  install -Dm755 "$_asahi/ryoku-firstboot-session" "$libexec/ryoku-firstboot-session"
  install -Dm755 "$_asahi/ryoku-firstboot-install" "$libexec/ryoku-firstboot-install"
  install -Dm644 "$_asahi/ryoku-firstboot.service" "$pkgdir/usr/lib/systemd/system/ryoku-firstboot.service"
  install -d "$pkgdir/usr/share/ryoku-asahi" "$pkgdir/usr/share/ryoku"
  _ref > "$pkgdir/usr/share/ryoku-asahi/ref"
  printf 'asahi\n' > "$pkgdir/usr/share/ryoku/variant"
  install -Dm644 "$_repo/fedora/packages/translations.tsv" "$pkgdir/usr/share/ryoku/fedora/packages/translations.tsv"
  for lib in common.sh i18n.sh accounts.sh; do
    install -Dm644 "$_lib/$lib" "$pkgdir/usr/share/ryoku/installation/backend/lib/$lib"
  done
}
