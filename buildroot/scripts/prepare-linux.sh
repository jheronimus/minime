#!/bin/sh

set -eu

BOOTSTRAP_PACKAGES="build-essential bison flex gettext texinfo unzip help2man rsync git curl ccache cmake mold ninja-build libelf-dev libssl-dev bc python3 python3-dev swig u-boot-tools cpio genimage mtools dosfstools lzip parted erofs-utils patchelf file wget libncurses-dev"

echo "Verifying Linux distribution on host..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    IS_DEBIAN=0
    IS_ALPINE=0

    case "${ID:-}" in
        debian|ubuntu|linuxmint|pop|neon|elementary|zorin)
            IS_DEBIAN=1
            ;;
        alpine)
            IS_ALPINE=1
            ;;
        *)
            case "${ID_LIKE:-}" in
                *debian*)
                    IS_DEBIAN=1
                    ;;
            esac
            ;;
    esac

    if [ "$IS_DEBIAN" -eq 1 ]; then
        echo "Host is a Debian-based Linux distribution (${NAME:-Linux})."
        echo "Installing packages on host (requires sudo)..."
        sudo apt-get update
        # shellcheck disable=SC2086
        sudo apt-get install -y $BOOTSTRAP_PACKAGES
        echo "Host is ready."
    elif [ "$IS_ALPINE" -eq 1 ]; then
        echo "Host is Alpine Linux."
        echo "Installing packages on host (requires sudo)..."
        
        ALPINE_PACKAGES="build-base bison flex gettext gettext-dev texinfo unzip help2man rsync git curl ccache cmake mold ninja elfutils-dev openssl-dev bc python3 python3-dev swig u-boot-tools cpio mtools dosfstools lzip parted patchelf findutils file wget ncurses-dev gcompat libc6-compat bash"
        
        sudo apk update
        # shellcheck disable=SC2086
        sudo apk add $ALPINE_PACKAGES
        echo "Host is ready."
    else
        echo "ERROR: Linux distribution '${NAME:-Unknown}' is not supported. Please install required packages manually." >&2
        exit 1
    fi
else
    echo "ERROR: /etc/os-release not found. Unable to identify distribution." >&2
    exit 1
fi
