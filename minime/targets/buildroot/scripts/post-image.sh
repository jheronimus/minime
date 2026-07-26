#!/bin/sh
# shellcheck shell=sh
# Minime Buildroot post-image script.

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
	echo "ERROR: -b option is required for post-image script." >&2
	exit 1
fi

MINIME_ROOT="$(cd "${BR2_EXTERNAL_MINIME_PATH}/../.." && pwd)"

# Stage system.erofs rootfs
echo "Building system.erofs for Buildroot..."
mkfs.erofs -z lz4hc "${BINARIES_DIR}/system.erofs" "${TARGET_DIR}"

# Assemble initramfs if missing
if [ ! -f "${BINARIES_DIR}/initramfs.img" ]; then
	echo "Assembling initramfs.img..."
	INITRD_STAGE=$(mktemp -d)
	mkdir -p "${INITRD_STAGE}/bin" "${INITRD_STAGE}/sbin" "${INITRD_STAGE}/lib" \
		"${INITRD_STAGE}/proc" "${INITRD_STAGE}/sys" "${INITRD_STAGE}/dev" \
		"${INITRD_STAGE}/tmp" "${INITRD_STAGE}/mnt/card" "${INITRD_STAGE}/mnt/system"

	cp -f "${TARGET_DIR}/bin/busybox" "${INITRD_STAGE}/bin/busybox"
	for app in sh mount mountpoint umount sleep reboot cp mkdir rm cat echo dd grep sync; do
		ln -sf busybox "${INITRD_STAGE}/bin/${app}"
	done
	ln -sf ../bin/busybox "${INITRD_STAGE}/sbin/switch_root"

	if [ -f "${MINIME_ROOT}/boards/common/initramfs-init.sh" ]; then
		cp -f "${MINIME_ROOT}/boards/common/initramfs-init.sh" "${INITRD_STAGE}/init"
		chmod +x "${INITRD_STAGE}/init"
	fi

	(cd "${INITRD_STAGE}" && find . | cpio -H newc -o >"${BINARIES_DIR}/initramfs.img")
	rm -rf "${INITRD_STAGE}"
fi

# Call central packager scripts
echo "Invoking central image builder for Buildroot ${BOARD_NAME}..."
"${MINIME_ROOT}/genimage/build-image.sh" \
	--target buildroot \
	--board "${BOARD_NAME}" \
	--input-dir "${BINARIES_DIR}" \
	--output-dir "${BINARIES_DIR}"

"${MINIME_ROOT}/genimage/build-update.sh" \
	--target buildroot \
	--board "${BOARD_NAME}" \
	--input-dir "${BINARIES_DIR}" \
	--output-dir "${BINARIES_DIR}"

echo "Buildroot post-image stage complete."
