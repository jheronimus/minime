#!/bin/sh

set -eu

usage() {
	echo "Usage: ${0##*/} -c GENIMAGE_CONFIG_FILE -b BOARD_NAME" >&2
}

GENIMAGE_CFG=""
BOARD_NAME=""
opts="$(getopt -n "${0##*/}" -o c:b: -- "$@")" || exit $?
eval set -- "$opts"
while true; do
	case "$1" in
	-c)
		GENIMAGE_CFG="$2"
		shift 2
		;;
	-b)
		BOARD_NAME="$2"
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
	echo "ERROR: -c option is required for post-build script." >&2
	exit 1
fi

if [ -z "$BOARD_NAME" ]; then
	echo "ERROR: -b option is required for post-build script." >&2
	exit 1
fi

BOARD_DIR="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/${BOARD_NAME}"
# 1. Generate and compile boot.cmd to boot.scr
BOOT_CMD_TEMPLATE="${ALPINE_DIR}/board/common/boot.cmd"
BOOT_ENV="${ALPINE_DIR}/board/${BOARD_NAME}/boot.env"

if [ ! -f "${BOOT_CMD_TEMPLATE}" ] || [ ! -f "${BOOT_ENV}" ]; then
	echo "ERROR: ${BOOT_CMD_TEMPLATE} or ${BOOT_ENV} is missing!" >&2
	exit 1
fi

BOOTARGS=""
DEFAULT_DEVICE=""
EXTRA_ENV=""
# shellcheck disable=SC1090
. "${BOOT_ENV}"

TMP_BOOT_CMD=$(mktemp)
sed -e "s|@BOOTARGS@|${BOOTARGS}|g" \
    -e "s|@DEFAULT_DEVICE@|${DEFAULT_DEVICE}|g" \
    -e "s|@EXTRA_ENV@|${EXTRA_ENV}|g" \
    "${BOOT_CMD_TEMPLATE}" > "${TMP_BOOT_CMD}"

mkimage -C none -A arm -T script -d "${TMP_BOOT_CMD}" "${BINARIES_DIR}/boot.scr"
rm -f "${TMP_BOOT_CMD}"

# 2. Add udev rule for Mali contiguous memory allocation (CMA) symlink
mkdir -p "${TARGET_DIR}/etc/udev/rules.d"
echo 'KERNEL=="default_cma_region", SYMLINK+="dma_heap/system-uncached"' >"${TARGET_DIR}/etc/udev/rules.d/99-mali.rules"

# 3. Create modules-load configuration files
mkdir -p "${TARGET_DIR}/etc/modules-load.d"

# Wifi drivers
cat <<'EOF' >"${TARGET_DIR}/etc/modules-load.d/wifi.conf"
cfg80211
mac80211
rtw88_core
rtw88_sdio
rtw88_8821c
rtw88_8821cs
EOF

# 3.5. Create modprobe options files to disable deep low-power saving states

mkdir -p "${TARGET_DIR}/etc/modprobe.d"
cat <<'EOF' >"${TARGET_DIR}/etc/modprobe.d/rtw88.conf"
options rtw88_core disable_lps_deep=y
options rtw88_sdio disable_lps_deep=y
EOF

# 4. Ensure proper symlink for DNS
ln -sf /tmp/resolv.conf "${TARGET_DIR}/etc/resolv.conf"

# 5. Create mount point for SD card
mkdir -p "${TARGET_DIR}/mnt/sdcard"

# 5.5. Install shared Realtek firmware from common tree if present
common_fw_dir="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/common/firmware"
if [ -d "${common_fw_dir}" ]; then
	find "${common_fw_dir}" -type f | while read -r fwfile; do
		rel="${fwfile#${common_fw_dir}/}"
		mkdir -p "${TARGET_DIR}/lib/firmware/$(dirname "${rel}")"
		cp -f "${fwfile}" "${TARGET_DIR}/lib/firmware/${rel}"
	done
fi

# Install the selected board's immutable Minime trait definitions.
if [ ! -f "${BOARD_DIR}/traits/platform.ini" ] ||
	[ ! -d "${BOARD_DIR}/traits/devices" ]; then
	echo "ERROR: ${BOARD_DIR}/traits is incomplete." >&2
	exit 1
fi
rm -rf "${TARGET_DIR}/usr/share/minime/traits"
mkdir -p "${TARGET_DIR}/usr/share/minime/traits"
cp -a "${BOARD_DIR}/traits/." "${TARGET_DIR}/usr/share/minime/traits/"

# Install shared Minime runtime scripts from the canonical source
scripts_src="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/common/scripts"
scripts_dst="${TARGET_DIR}/usr/share/minime/scripts"
mkdir -p "${scripts_dst}"
cp "${scripts_src}/wifi.sh" "${scripts_src}/ui.sh" "${scripts_src}/traits.sh" \
	"${scripts_dst}/"
chmod +x "${scripts_dst}/wifi.sh" "${scripts_dst}/ui.sh" "${scripts_dst}/traits.sh"

# 6. Run optional board-specific post-build hook if it exists
if [ -f "${BR_BOARD_DIR}/post-build.sh" ]; then
	echo "Running board-specific post-build hook for $(basename "${BOARD_DIR}")..."
	# Export variables so the hook script can use them
	export TARGET_DIR BINARIES_DIR BR_BOARD_DIR BR2_EXTERNAL_MINIME_PATH
	sh "${BR_BOARD_DIR}/post-build.sh"
fi

echo "Post-build stage completed successfully."
