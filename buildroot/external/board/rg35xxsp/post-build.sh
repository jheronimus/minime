#!/bin/sh

set -eu

BOARD_DIR="$(dirname "$0")"

# 1. Compile boot.cmd to boot.scr
mkimage -C none -A arm -T script -d "${BOARD_DIR}/boot.cmd" "${BINARIES_DIR}/boot.scr"

# 2. Add udev rule for Mali contiguous memory allocation (CMA) symlink
mkdir -p "${TARGET_DIR}/etc/udev/rules.d"
echo 'KERNEL=="default_cma_region", SYMLINK+="dma_heap/system-uncached"' > "${TARGET_DIR}/etc/udev/rules.d/99-mali.rules"

# 3. Create modules-load configuration files
mkdir -p "${TARGET_DIR}/etc/modules-load.d"

# Wifi drivers
cat << 'EOF' > "${TARGET_DIR}/etc/modules-load.d/wifi.conf"
cfg80211
mac80211
rtw88_core
rtw88_sdio
rtw88_8821c
rtw88_8821cs
EOF

# Mali kernel driver
cat << 'EOF' > "${TARGET_DIR}/etc/modules-load.d/mali.conf"
mali_kbase
EOF

# 4. Clean up OpenRC-specific files in overlay if they were copied
rm -rf "${TARGET_DIR}/etc/conf.d"
rm -f "${TARGET_DIR}/etc/inittab" # We use standard Buildroot /etc/inittab
rm -f "${TARGET_DIR}/etc/mdev.conf" # We use udev, not mdev

# Ensure proper symlink for DNS
ln -sf /tmp/resolv.conf "${TARGET_DIR}/etc/resolv.conf"

echo "Post-build stage completed successfully."
