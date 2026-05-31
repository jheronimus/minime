#!/bin/sh

set -eu

usage() {
	echo "Usage: ${0##*/} -c GENIMAGE_CONFIG_FILE" >&2
}

GENIMAGE_CFG=""
opts="$(getopt -n "${0##*/}" -o c: -- "$@")" || exit $?
eval set -- "$opts"
while true; do
	case "$1" in
		-c)
			GENIMAGE_CFG="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [ -z "$GENIMAGE_CFG" ]; then
	echo "ERROR: -c option is required for post-build script to determine board config." >&2
	exit 1
fi

BOARD_DIR="$(dirname "$GENIMAGE_CFG")"

if [ ! -f "${BOARD_DIR}/boot.cmd" ]; then
	echo "ERROR: ${BOARD_DIR}/boot.cmd is missing!" >&2
	exit 1
fi

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

# 6. Run optional board-specific post-build hook if it exists
if [ -f "${BOARD_DIR}/post-build.sh" ]; then
	echo "Running board-specific post-build hook for $(basename "${BOARD_DIR}")..."
	# Export variables so the hook script can use them
	export TARGET_DIR BINARIES_DIR BOARD_DIR BR2_EXTERNAL_MINIME_PATH
	sh "${BOARD_DIR}/post-build.sh"
fi

echo "Post-build stage completed successfully."
