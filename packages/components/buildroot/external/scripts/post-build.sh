#!/bin/sh
# shellcheck shell=sh
# Minime Buildroot post-build script.

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

MINIME_ROOT="${MINIME_ROOT:-$(cd "${BR2_EXTERNAL_MINIME_PATH}/../../../.." && pwd)}"
BOARDS_DIR="${MINIME_ROOT}/packages/components/boards"
BOARD_DIR="${BOARDS_DIR}/${BOARD_NAME}"
COMMON_DIR="${BOARDS_DIR}/common"

if [ ! -d "${BOARD_DIR}" ]; then
	echo "ERROR: Board directory ${BOARD_DIR} missing!" >&2
	exit 1
fi

# 1. Mali CMA udev rule
mkdir -p "${TARGET_DIR}/etc/udev/rules.d"
echo 'KERNEL=="default_cma_region", SYMLINK+="dma_heap/system-uncached"' >"${TARGET_DIR}/etc/udev/rules.d/99-mali.rules"

# 2. Board-specific overlay
if [ -d "${BOARD_DIR}/overlay" ]; then
	cp -a "${BOARD_DIR}/overlay/." "${TARGET_DIR}/"
fi

# 3. DNS symlink & SD card mount point.
#    /etc/resolv.conf points at openresolv's runtime output (iwd pushes the
#    DHCP DNS servers to it via NameResolvingService=resolvconf).
ln -sf /run/resolvconf/resolv.conf "${TARGET_DIR}/etc/resolv.conf"
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
if [ -f "${COMMON_DIR}/scripts/log-boot.sh" ]; then
	cp -f "${COMMON_DIR}/scripts/log-boot.sh" "${TARGET_DIR}/usr/share/minime/scripts/"
	chmod +x "${TARGET_DIR}/usr/share/minime/scripts/log-boot.sh"
fi
if [ -f "${COMMON_DIR}/scripts/collect-diagnostics.sh" ]; then
	cp -f "${COMMON_DIR}/scripts/collect-diagnostics.sh" "${TARGET_DIR}/usr/share/minime/scripts/"
	chmod +x "${TARGET_DIR}/usr/share/minime/scripts/collect-diagnostics.sh"
fi
if [ -f "${COMMON_DIR}/scripts/audio.sh" ]; then
	cp -f "${COMMON_DIR}/scripts/audio.sh" "${TARGET_DIR}/usr/share/minime/scripts/"
	chmod +x "${TARGET_DIR}/usr/share/minime/scripts/audio.sh"
fi
if [ -f "${COMMON_DIR}/scripts/audio-monitor.sh" ]; then
	cp -f "${COMMON_DIR}/scripts/audio-monitor.sh" "${TARGET_DIR}/usr/share/minime/scripts/"
	chmod +x "${TARGET_DIR}/usr/share/minime/scripts/audio-monitor.sh"
fi

# 7. OpenRC SysV Cleanup
# Clean up legacy SysV scripts created by some packages, as we use pure OpenRC
TARGET_INITD="${TARGET_DIR}/etc/init.d"
TARGET_RUNLEVELS="${TARGET_DIR}/etc/runlevels"
rm -f "${TARGET_INITD}/S"* "${TARGET_RUNLEVELS}"/*/sysv-rcs "${TARGET_INITD}/sysv-rcs" 2>/dev/null || true

# 8. Touch a marker file used by initramfs-init.sh to advance system time on cold
#    boot if the hardware RTC is in the past (prevents OpenRC clock skew warnings).
touch "${TARGET_DIR}/.build_time"

# 9. Ensure dbus user and group exist for dbus-daemon
if [ -f "${TARGET_DIR}/etc/passwd" ] && ! grep -q '^dbus:' "${TARGET_DIR}/etc/passwd"; then
	echo 'dbus:x:81:81:dbus:/run/dbus:/bin/false' >>"${TARGET_DIR}/etc/passwd"
fi
if [ -f "${TARGET_DIR}/etc/group" ] && ! grep -q '^dbus:' "${TARGET_DIR}/etc/group"; then
	echo 'dbus:x:81:dbus' >>"${TARGET_DIR}/etc/group"
fi
if [ -f "${TARGET_DIR}/etc/shadow" ] && ! grep -q '^dbus:' "${TARGET_DIR}/etc/shadow"; then
	echo 'dbus:*:19000:0:99999:7:::' >>"${TARGET_DIR}/etc/shadow"
fi

echo "Buildroot post-build stage complete."
