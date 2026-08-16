#!/bin/sh
# shellcheck shell=sh
# Minime Buildroot system-image script.

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
	echo "ERROR: -b option is required for system-image script." >&2
	exit 1
fi

MINIME_ROOT="${MINIME_ROOT:-$(cd "${BR2_EXTERNAL_MINIME_PATH}/../../../.." && pwd)}"

# Stage system.erofs rootfs
echo "Building system.erofs for Buildroot..."
mkfs.erofs -z lz4hc "${BINARIES_DIR}/system.erofs" "${TARGET_DIR}"

# Always reassemble the initramfs so stale cached copies never survive.
echo "Assembling initramfs.img..."
INITRD_STAGE=$(mktemp -d)
mkdir -p "${INITRD_STAGE}/bin" "${INITRD_STAGE}/sbin" "${INITRD_STAGE}/lib" \
	"${INITRD_STAGE}/proc" "${INITRD_STAGE}/sys" "${INITRD_STAGE}/dev" \
	"${INITRD_STAGE}/tmp" "${INITRD_STAGE}/mnt/card" "${INITRD_STAGE}/mnt/system"

cp -f "${TARGET_DIR}/bin/busybox" "${INITRD_STAGE}/bin/busybox"
for app in sh mount mountpoint umount sleep reboot cp mkdir rm cat echo dd grep sync chroot date blkid; do
	ln -sf busybox "${INITRD_STAGE}/bin/${app}"
done
ln -sf ../bin/busybox "${INITRD_STAGE}/sbin/switch_root"

FSCK_FAT=""
for candidate in "${TARGET_DIR}/sbin/fsck.fat" "${TARGET_DIR}/usr/sbin/fsck.fat"; do
	if [ -x "${candidate}" ]; then
		FSCK_FAT="${candidate}"
		break
	fi
done
if [ -z "${FSCK_FAT}" ]; then
	echo "ERROR: fsck.fat not found -- enable BR2_PACKAGE_DOSFSTOOLS_FSCK_FAT" >&2
	exit 1
fi
cp -a "${FSCK_FAT}" "${INITRD_STAGE}/sbin/fsck.fat"

if [ -d "${TARGET_DIR}/lib" ]; then
	cp -d "${TARGET_DIR}/lib/ld-"*.so* "${INITRD_STAGE}/lib/" 2>/dev/null || true
	cp -d "${TARGET_DIR}/lib/libc.so"* "${INITRD_STAGE}/lib/" 2>/dev/null || true
	cp -d "${TARGET_DIR}/lib/libm.so"* "${INITRD_STAGE}/lib/" 2>/dev/null || true
	cp -d "${TARGET_DIR}/lib/libresolv.so"* "${INITRD_STAGE}/lib/" 2>/dev/null || true
fi

if [ -x "${TARGET_DIR}/usr/bin/bootsplash" ]; then
	mkdir -p "${INITRD_STAGE}/usr/bin"
	cp -a "${TARGET_DIR}/usr/bin/bootsplash" "${INITRD_STAGE}/usr/bin/bootsplash"
fi

if [ -f "${TARGET_DIR}/usr/share/minime/traits/platform.ini" ]; then
	mkdir -p "${INITRD_STAGE}/etc"
	cp -f "${TARGET_DIR}/usr/share/minime/traits/platform.ini" "${INITRD_STAGE}/etc/traits"
fi

if [ -f "${MINIME_ROOT}/minime/boards/common/initramfs-init.sh" ]; then
	cp -f "${MINIME_ROOT}/minime/boards/common/initramfs-init.sh" "${INITRD_STAGE}/init"
	chmod +x "${INITRD_STAGE}/init"
fi

(cd "${INITRD_STAGE}" && find . | cpio -H newc -o >"${BINARIES_DIR}/initramfs.img")
rm -rf "${INITRD_STAGE}"

echo "Buildroot system-image stage complete."
