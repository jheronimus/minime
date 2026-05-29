#!/bin/bash

set -euo pipefail

# Bootstrap packages list
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

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
    echo "Detected macOS host. Setting up OrbStack VM..."
    
    # Check if OrbStack CLI is installed
    if ! command -v orb >/dev/null 2>&1; then
        echo "ERROR: OrbStack CLI 'orb' not found. Please install OrbStack first." >&2
        exit 1
    fi
    
    ORB_MACHINE="${ORB_MACHINE:-builder}"
    ORB_DISTRO="${ORB_DISTRO:-debian:trixie}"
    ORB_ARCH="${ORB_ARCH:-arm64}"
    ORB_USER="${ORB_USER:-$(id -un)}"
    
    if ! orb list --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
        echo "Creating OrbStack VM '$ORB_MACHINE' ($ORB_DISTRO/$ORB_ARCH)..."
        orb create -a "$ORB_ARCH" -u "$ORB_USER" "$ORB_DISTRO" "$ORB_MACHINE"
    fi
    
    if ! orb list --running --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
        orb start "$ORB_MACHINE" >/dev/null
    fi
    
    echo "Installing build packages inside the OrbStack VM..."
    orb -m "$ORB_MACHINE" -u root sh -lc "
        set -eu
        apt-get update
        apt-get install -y ${BOOTSTRAP_PACKAGES[*]}
    "
    echo "OrbStack VM is ready."

elif [ "$OS" = "Linux" ]; then
    echo "Detected Linux host. Verifying Debian-based distribution..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # Check ID or ID_LIKE for debian/ubuntu/mint/etc
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
else
    echo "ERROR: Unsupported OS '$OS'" >&2
    exit 1
fi
