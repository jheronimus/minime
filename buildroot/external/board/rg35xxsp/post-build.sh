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

# 3.5. Create modprobe options files to disable deep low-power saving states
mkdir -p "${TARGET_DIR}/etc/modprobe.d"
cat << 'EOF' > "${TARGET_DIR}/etc/modprobe.d/rtw88.conf"
options rtw88_core disable_lps_deep=y
options rtw88_sdio disable_lps_deep=y
EOF


# 4. Ensure proper symlink for DNS
ln -sf /tmp/resolv.conf "${TARGET_DIR}/etc/resolv.conf"

# 5. Create mount point for SD card
mkdir -p "${TARGET_DIR}/mnt/sdcard"

# 6. Remove default telnet init script to avoid conflict with custom S50telnetd
rm -f "${TARGET_DIR}/etc/init.d/S50telnet"

# 7. Remove any dropbear target files to ensure it is completely disabled/absent
rm -rf "${TARGET_DIR}/etc/dropbear"
rm -f "${TARGET_DIR}/etc/init.d/S50dropbear"
rm -f "${TARGET_DIR}/usr/bin/dropbearconvert"
rm -f "${TARGET_DIR}/usr/bin/dropbearkey"
rm -f "${TARGET_DIR}/usr/sbin/dropbear"

echo "Post-build stage completed successfully."
