#!/bin/bash

set -euo pipefail

BOOTSTRAP_PACKAGES=(
    build-essential
    bison
    flex
    gettext
    texinfo
    unzip
    help2man
    rsync
    git
    curl
    ccache
    cmake
    mold
    ninja-build
    libelf-dev
    libssl-dev
    bc
    python3
    python3-dev
    swig
    u-boot-tools
    cpio
    genimage
    mtools
    dosfstools
    lzip
    parted
    erofs-utils
    patchelf
    file
    wget
    libncurses-dev
)

echo "Verifying Debian-based distribution on Linux host..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    IS_DEBIAN=0
    if [[ "${ID:-}" =~ ^(debian|ubuntu|linuxmint|pop|neon|elementary|zorin)$ ]]; then
        IS_DEBIAN=1
    elif [[ "${ID_LIKE:-}" =~ debian ]]; then
        IS_DEBIAN=1
    fi

    if [ "$IS_DEBIAN" -eq 1 ]; then
        echo "Host is a Debian-based Linux distribution ($NAME)."
        echo "Installing packages on host (requires sudo)..."
        sudo apt-get update
        sudo apt-get install -y "${BOOTSTRAP_PACKAGES[@]}"
        echo "Host is ready."
    else
        echo "ERROR: Linux distribution '$NAME' is not Debian-based. Please install required packages manually." >&2
        exit 1
    fi
else
    echo "ERROR: /etc/os-release not found. Unable to identify distribution." >&2
    exit 1
fi
