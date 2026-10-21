Name:           gpk
Version:        0.6.10
Release:        2%{?dist}
Summary:        Cross-distribution package manager dashboard
License:        GPL-3.0-or-later
URL:            https://github.com/neur0map/glazepkg
Source0:        %{url}/releases/download/v%{version}/gpk-linux-amd64#/gpk-%{version}-x86_64
Source1:        https://raw.githubusercontent.com/neur0map/glazepkg/v%{version}/LICENSE#/gpk-LICENSE
Source2:        %{url}/releases/download/v%{version}/gpk-linux-arm64#/gpk-%{version}-aarch64
ExclusiveArch:  x86_64 aarch64
%global debug_package %{nil}

Provides:       gpk
Conflicts:      gpk-bin
Obsoletes:      gpk-bin < %{version}-%{release}

%description
GlazePKG provides one searchable terminal dashboard for package managers on
Linux, including dnf and xbps.

%prep
cp -p %{SOURCE1} LICENSE

%build

%install
install -Dpm0755 %{_sourcedir}/gpk-%{version}-%{_arch} %{buildroot}%{_bindir}/gpk

%files
%license LICENSE
%{_bindir}/gpk
