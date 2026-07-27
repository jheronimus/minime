#!/bin/sh
# shellcheck shell=sh
# Minime Buildroot post-build script.

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
		export GENIMAGE_CFG="$2"
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

if [ -z "$BOARD_NAME" ]; then
	echo "ERROR: -b option is required for post-build script." >&2
	exit 1
fi

MINIME_ROOT="${MINIME_ROOT:-$(cd "${BR2_EXTERNAL_MINIME_PATH}/../../../.." && pwd)}"
BUILDROOT_ROOT="${BUILDROOT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BOARDS_DIR="${MINIME_ROOT}/minime/boards"
BOARD_DIR="${BOARDS_DIR}/${BOARD_NAME}"
COMMON_DIR="${BOARDS_DIR}/common"

if [ ! -d "${BOARD_DIR}" ]; then
	echo "ERROR: Board directory ${BOARD_DIR} missing!" >&2
	exit 1
fi

# 1. Mali CMA udev rule
mkdir -p "${TARGET_DIR}/etc/udev/rules.d"
echo 'KERNEL=="default_cma_region", SYMLINK+="dma_heap/system-uncached"' >"${TARGET_DIR}/etc/udev/rules.d/99-mali.rules"

# 2. Shared WiFi & Sysctl Config
mkdir -p "${TARGET_DIR}/etc/modules-load.d" "${TARGET_DIR}/etc/modprobe.d" "${TARGET_DIR}/etc/sysctl.d"
[ -f "${COMMON_DIR}/overlay/etc/modules-load.d/wifi.conf" ] && cp -f "${COMMON_DIR}/overlay/etc/modules-load.d/wifi.conf" "${TARGET_DIR}/etc/modules-load.d/" || true
[ -f "${COMMON_DIR}/overlay/etc/modprobe.d/rtw88.conf" ] && cp -f "${COMMON_DIR}/overlay/etc/modprobe.d/rtw88.conf" "${TARGET_DIR}/etc/modprobe.d/" || true
[ -f "${COMMON_DIR}/overlay/etc/sysctl.d/00-minime.conf" ] && cp -f "${COMMON_DIR}/overlay/etc/sysctl.d/00-minime.conf" "${TARGET_DIR}/etc/sysctl.d/" || true

# 3. DNS symlink & SD card mount point
ln -sf /tmp/resolv.conf "${TARGET_DIR}/etc/resolv.conf"
mkdir -p "${TARGET_DIR}/mnt/sdcard"

# 4. Shared Realtek firmware
if [ -d "${COMMON_DIR}/firmware" ]; then
	find "${COMMON_DIR}/firmware" -type f | while read -r fwfile; do
		rel="${fwfile#${COMMON_DIR}/firmware/}"
		mkdir -p "${TARGET_DIR}/lib/firmware/$(dirname "${rel}")"
		cp -f "${fwfile}" "${TARGET_DIR}/lib/firmware/${rel}"
	done
fi

# 5. Traits definitions
if [ -d "${BOARD_DIR}/traits" ]; then
	rm -rf "${TARGET_DIR}/usr/share/minime/traits"
	mkdir -p "${TARGET_DIR}/usr/share/minime/traits"
	cp -a "${BOARD_DIR}/traits/." "${TARGET_DIR}/usr/share/minime/traits/"
	echo "gpu_driver=mali_kbase" >>"${TARGET_DIR}/usr/share/minime/traits/platform.ini"
fi

# 6. Shared Minime runtime scripts
mkdir -p "${TARGET_DIR}/usr/share/minime/scripts"
if [ -f "${COMMON_DIR}/scripts/device.sh" ]; then
	cp -f "${COMMON_DIR}/scripts/device.sh" "${TARGET_DIR}/usr/share/minime/scripts/"
	chmod +x "${TARGET_DIR}/usr/share/minime/scripts/device.sh"
fi

# 7. OpenRC Init Services
TARGET_INITD="${TARGET_DIR}/etc/init.d"
TARGET_RUNLEVELS="${TARGET_DIR}/etc/runlevels"
mkdir -p "${TARGET_INITD}" "${TARGET_RUNLEVELS}/boot" "${TARGET_RUNLEVELS}/default"

if [ -d "${COMMON_DIR}/overlay/etc/init.d" ]; then
	for svc in modules fb-unblank traits wifi ftpd telnetd bluetooth gpudriver ui; do
		if [ -f "${COMMON_DIR}/overlay/etc/init.d/${svc}" ]; then
			cp -f "${COMMON_DIR}/overlay/etc/init.d/${svc}" "${TARGET_INITD}/${svc}"
			chmod 0755 "${TARGET_INITD}/${svc}"
		fi
	done
fi

# Clean up legacy SysV scripts
rm -f "${TARGET_INITD}/S"* "${TARGET_RUNLEVELS}"/*/sysv-rcs "${TARGET_INITD}/sysv-rcs"

# Runlevel symlinks
for svc in modules fb-unblank traits wifi ftpd telnetd gpudriver bluetooth; do
	[ -f "${TARGET_INITD}/${svc}" ] && ln -sf "../../init.d/${svc}" "${TARGET_RUNLEVELS}/boot/${svc}" || true
done
[ -f "${TARGET_INITD}/ui" ] && ln -sf "../../init.d/ui" "${TARGET_RUNLEVELS}/default/ui" || true

echo "Buildroot post-build stage complete."
