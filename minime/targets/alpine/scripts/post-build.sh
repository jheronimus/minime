#!/bin/sh
# shellcheck shell=sh
# Minime Alpine post-build script.

set -eu

usage() {
	echo "Usage: ${0##*/} -b BOARD_NAME" >&2
}

BOARD_NAME=""
opts="$(getopt -n "${0##*/}" -o b: -- "$@")" || exit $?
eval set -- "$opts"
while true; do
	case "$1" in
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

if [ -z "$BOARD_NAME" ]; then
	echo "ERROR: -b option is required for post-build script." >&2
	exit 1
fi

TARGET_DIR="${TARGET_DIR:-${ALPINE_ROOTFS_DIR}}"
if [ -z "${TARGET_DIR}" ] || [ ! -d "${TARGET_DIR}" ]; then
	echo "ERROR: TARGET_DIR or ALPINE_ROOTFS_DIR is not set or missing." >&2
	exit 1
fi

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
BOARDS_DIR="${MINIME_ROOT}/minime/boards"
BOARD_DIR="${BOARDS_DIR}/${BOARD_NAME}"
COMMON_DIR="${BOARDS_DIR}/common"

if [ ! -d "${BOARD_DIR}" ]; then
	echo "ERROR: Board directory ${BOARD_DIR} missing!" >&2
	exit 1
fi

# 1. Install the board's immutable trait payload.
if [ -d "${BOARD_DIR}/traits" ]; then
	rm -rf "${TARGET_DIR}/usr/share/minime/traits"
	mkdir -p "${TARGET_DIR}/usr/share/minime/traits"
	cp -a "${BOARD_DIR}/traits/." "${TARGET_DIR}/usr/share/minime/traits/"
	echo "gpu_driver=panfrost" >>"${TARGET_DIR}/usr/share/minime/traits/platform.ini"
fi

# 2. Install the Minime overlay (OpenRC services, system config, udev rules).
if [ -d "${COMMON_DIR}/overlay" ]; then
	cp -a "${COMMON_DIR}/overlay/." "${TARGET_DIR}/"
fi

# 3. Install board-specific overlay if present.
if [ -d "${BOARD_DIR}/overlay" ]; then
	cp -a "${BOARD_DIR}/overlay/." "${TARGET_DIR}/"
fi

# 4. Install shared utility scripts.
mkdir -p "${TARGET_DIR}/usr/share/minime/scripts"
[ -f "${COMMON_DIR}/scripts/device.sh" ] && install -m 0755 "${COMMON_DIR}/scripts/device.sh" \
	"${TARGET_DIR}/usr/share/minime/scripts/" || true
[ -f "${COMMON_DIR}/scripts/thermal-watchdog" ] && install -m 0755 "${COMMON_DIR}/scripts/thermal-watchdog" \
	"${TARGET_DIR}/usr/share/minime/scripts/" || true
[ -f "${COMMON_DIR}/scripts/log-boot.sh" ] && install -m 0755 "${COMMON_DIR}/scripts/log-boot.sh" \
	"${TARGET_DIR}/usr/share/minime/scripts/" || true
[ -f "${COMMON_DIR}/scripts/collect-diagnostics.sh" ] && install -m 0755 "${COMMON_DIR}/scripts/collect-diagnostics.sh" \
	"${TARGET_DIR}/usr/share/minime/scripts/" || true

# 5. Replace build-time resolv.conf with symlink to allow runtime DHCP DNS updates
ln -sf /tmp/resolv.conf "${TARGET_DIR}/etc/resolv.conf"

# 6. Touch a marker file to represent the absolute latest timestamp in the rootfs.
touch "${TARGET_DIR}/.build_time"

echo "Alpine post-build stage complete."
