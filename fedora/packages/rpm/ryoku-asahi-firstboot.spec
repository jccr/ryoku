Name:           ryoku-asahi-firstboot
Version:        0.1
Release:        1%{?dist}
Summary:        Ryoku first-boot setup for Fedora Asahi Remix
License:        GPL-3.0-or-later
URL:            https://ryoku.dev
Source0:        ryoku-%{version}.tar.gz
%global debug_package %{nil}
# The Asahi installer delivers it as an extra to an Apple Silicon Mac.
ExclusiveArch:  aarch64
BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  golang >= 1.26.4
# Installed offline at first boot, before the network is up, so every runtime
# need is already part of the Fedora Asahi Remix Minimal image.
Requires:       btrfs-progs
Requires:       curl
Requires:       NetworkManager
Requires:       NetworkManager-wifi
Requires:       sudo
Requires:       systemd
Requires:       util-linux

%description
The Ryoku installer wizard on the first boot of a Mac running Fedora Asahi
Remix: it replaces initial-setup, creates the accounts and installs the Ryoku
desktop.

%prep
%setup -q -n ryoku-%{version}

%build
export RYOKU_PKGVER=%{version}
bash fedora/packages/rpm/stage-package.sh %{name} "$PWD/stage" %{_libdir}

%install
cp -a stage/. %{buildroot}/
find %{buildroot} -type f -o -type l | sed 's|^%{buildroot}||' > rpm-files

%post
# asahi-extras-firstboot installs this while the first boot is under way and
# initial-setup may already own tty1; the Ryoku wizard takes its place now.
if [ "$1" -eq 1 ] && [ -d /run/systemd/system ]; then
  systemctl daemon-reload >/dev/null 2>&1 || :
  systemctl disable initial-setup.service >/dev/null 2>&1 || :
  systemctl enable ryoku-firstboot.service >/dev/null 2>&1 || :
  systemctl --no-block start ryoku-firstboot.service >/dev/null 2>&1 || :
fi

%files -f rpm-files
