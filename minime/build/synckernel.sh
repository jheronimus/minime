#!/bin/sh
# Sync kernel version from Alpine stable to local APKBUILD and Buildroot
# Max SLOC: 100

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APKBUILD_PATH="${ROOT_DIR}/minime/targets/alpine/aports/tinykernel/APKBUILD"
CONFIG_PATH="${ROOT_DIR}/minime/targets/buildroot/external/configs/common.config"
ALPINE_URL="https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/linux-stable/APKBUILD"

echo "Fetching latest Alpine stable version from ${ALPINE_URL}..."
content=$(curl -sSfL "$ALPINE_URL") || { echo "Failed to fetch Alpine APKBUILD" >&2; exit 1; }

version=$(echo "$content" | grep -E '^pkgver=' | cut -d= -f2 | head -n 1)
if [ -z "$version" ]; then
    echo "Could not resolve latest Alpine stable version." >&2
    exit 1
fi
echo "Latest resolved kernel version: $version"

major=$(echo "$version" | cut -d. -f1)
dl_url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${version}.tar.xz"
dl_filename="linux-${version}.tar.xz"

echo "Downloading and computing sha512 hash for $dl_url..."
sha512=$(curl -sSfL "$dl_url" | sha512sum | awk '{print $1}')

if [ -z "$sha512" ]; then
    echo "Failed to compute sha512 hash." >&2
    exit 1
fi

echo "Updating APKBUILD at $APKBUILD_PATH"
# Use compatible sed in-place edit for both GNU/BSD
sed -i.bak -e "s/^pkgver=.*/pkgver=$version/" "$APKBUILD_PATH"
sed -i.bak -e "s/^sha512sums=.*/sha512sums=\"$sha512  $dl_filename\"/" "$APKBUILD_PATH"
rm -f "${APKBUILD_PATH}.bak"

echo "Updating Buildroot config at $CONFIG_PATH"
sed -i.bak -e "s/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=\".*\"/BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=\"$version\"/" "$CONFIG_PATH"
rm -f "${CONFIG_PATH}.bak"

echo "Done."
