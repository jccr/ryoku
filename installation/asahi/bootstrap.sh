#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Ryoku's Asahi bootstrap: the Asahi project's scripts/bootstrap-prod.sh with
# the OS list pointed at Ryoku's, the installer pinned to a checked release,
# and no install report sent to the Asahi project. The installer that
# partitions the Mac is the Asahi project's own, unmodified.
#
#   curl -fsSL https://repo.ryoku.dev/stable/asahi/bootstrap.sh | sh
#   RYOKU_CHANNEL=testing sh bootstrap.sh

# Truncation guard
if true; then
    set -e

    if [ ! -e /System ]; then
        echo "You appear to be running this script from Linux or another non-macOS system."
        echo "Asahi Linux can only be installed from macOS (or recoveryOS)."
        exit 1
    fi

    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    if ! curl --no-progress-meter file:/// >/dev/null 2>&1; then
        echo "Your version of cURL is too old. This usually means your macOS is very out"
        echo "of date. Installing Asahi Linux requires at least macOS version 13.5."
        exit 1
    fi

    RYOKU_CHANNEL=${RYOKU_CHANNEL:-stable}
    PKG_VER=v0.9.2
    PKG_SHA256=484d999e53b4aef27d17c4478e49567e96842f8a6cb35c073a0df5bf0bbe8276

    export INSTALLER_BASE=https://cdn.asahilinux.org/installer
    export INSTALLER_DATA="https://repo.ryoku.dev/stable/asahi/$RYOKU_CHANNEL/installer_data.json"
    export REPO_BASE=https://cdn.asahilinux.org

    #TMP="$(mktemp -d)"
    TMP=/tmp/asahi-install

    echo
    echo "Ryoku for Apple Silicon ($RYOKU_CHANNEL)"
    echo "  Asahi installer $PKG_VER from $INSTALLER_BASE"
    echo "  Ryoku OS list from $INSTALLER_DATA"
    echo "  Nothing on the disk changes until you confirm in the installer."
    echo
    echo "Bootstrapping installer:"

    if [ -e "$TMP" ]; then
        mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$TMP"
    cd "$TMP"

    echo "  Version: $PKG_VER"

    PKG="installer-$PKG_VER.tar.gz"

    echo "  Downloading..."

    curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
    if ! echo "$PKG_SHA256  $PKG" | shasum -a 256 -c - >/dev/null; then
        echo "    The Asahi installer does not match the release this script was checked"
        echo "    against. Nothing was changed; get a current script from Ryoku."
        exit 1
    fi
    curl --no-progress-meter -L -o installer_data.json "$INSTALLER_DATA"

    echo "  Extracting..."

    tar xf "$PKG"

    echo "  Initializing..."
    echo

    if [ "$USER" != "root" ]; then
        echo "The installer needs to run as root."
        echo "Please enter your sudo password if prompted."
        exec caffeinate -dis sudo -E ./install.sh "$@"
    else
        exec caffeinate -dis ./install.sh "$@"
    fi
fi
