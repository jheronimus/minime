#!/bin/sh
# shellcheck shell=sh
# Minime Central Image Builder (genimage)
#
# Usage:
#   genimage.sh --target <alpine|buildroot> --board <h700|rk3326|rk3566> \
#                  --input-dir <dir> --output-dir <dir>

set -eu

usage() {
	echo "Usage: ${0##*/} --target <alpine|buildroot> --board <h700|rk3326|rk3566> --input-dir <dir> --output-dir <dir>" >&2
	exit 1
}

TARGET=""
BOARD=""
INPUT_DIR=""
OUTPUT_DIR=""

while [ $# -gt 0 ]; do
	case "$1" in
	--target)
		TARGET="$2"
		shift 2
		;;
	--board)
		BOARD="$2"
		shift 2
		;;
	--input-dir)
		INPUT_DIR="$2"
		shift 2
		;;
	--output-dir)
		OUTPUT_DIR="$2"
		shift 2
		;;
	*)
		usage
		;;
	esac
done

if [ -z "$TARGET" ] || [ -z "$BOARD" ] || [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
	usage
fi

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD_DIR="${MINIME_ROOT}/minime/boards/${BOARD}"
COMMON_DIR="${MINIME_ROOT}/minime/boards/common"
UBOOT_OUT_DIR="${MINIME_ROOT}/minime/uboot/out/${BOARD}"

mkdir -p "${OUTPUT_DIR}"

WORK_TMP="$(mktemp -d)"
cleanup() {
	rm -rf "${WORK_TMP}"
}
trap cleanup EXIT

BINARIES_DIR="${WORK_TMP}/binaries"
ROOTPATH_TMP="${WORK_TMP}/rootpath"
USERDATA_STAGE="${ROOTPATH_TMP}/userdata"

mkdir -p "${BINARIES_DIR}" "${USERDATA_STAGE}/.minime/config" "${USERDATA_STAGE}/.minime/devices"

# 1. Stage Kernel, Initramfs, EROFS System RootFS
KERNEL_SRC=""
for k in Image zImage; do
	if [ -f "${INPUT_DIR}/${k}" ]; then
		KERNEL_SRC="${INPUT_DIR}/${k}"
		break
	fi
done
[ -f "${KERNEL_SRC}" ] || {
	echo "ERROR: Kernel binary (Image) missing in ${INPUT_DIR}" >&2
	exit 1
}

INITRAMFS_SRC=""
for i in initramfs.img initramfs; do
	if [ -f "${INPUT_DIR}/${i}" ]; then
		INITRAMFS_SRC="${INPUT_DIR}/${i}"
		break
	fi
done
[ -f "${INITRAMFS_SRC}" ] || {
	echo "ERROR: initramfs missing in ${INPUT_DIR}" >&2
	exit 1
}

SYSTEM_SRC=""
for s in system.erofs rootfs.erofs; do
	if [ -f "${INPUT_DIR}/${s}" ]; then
		SYSTEM_SRC="${INPUT_DIR}/${s}"
		break
	fi
done
[ -f "${SYSTEM_SRC}" ] || {
	echo "ERROR: EROFS system rootfs missing in ${INPUT_DIR}" >&2
	exit 1
}

cp -f "${KERNEL_SRC}" "${USERDATA_STAGE}/.minime/kernel"
cp -f "${INITRAMFS_SRC}" "${USERDATA_STAGE}/.minime/initramfs"
cp -f "${SYSTEM_SRC}" "${USERDATA_STAGE}/.minime/system"

# 2. Stage Platform Device Trees (DTBs)
DTB_COUNT=0
if [ -d "${INPUT_DIR}/devices" ]; then
	cp -f "${INPUT_DIR}/devices/"*.dtb "${USERDATA_STAGE}/.minime/devices/" 2>/dev/null || true
fi
cp -f "${INPUT_DIR}"/*.dtb "${USERDATA_STAGE}/.minime/devices/" 2>/dev/null || true

for dtb_file in "${USERDATA_STAGE}/.minime/devices/"*.dtb; do
	[ -f "${dtb_file}" ] && DTB_COUNT=$((DTB_COUNT + 1))
done

if [ "$DTB_COUNT" -eq 0 ]; then
	echo "WARNING: No DTBs found in ${INPUT_DIR}" >&2
fi

# Stage default DTB link
DEFAULT_DEVICE="${DEFAULT_DEVICE:-}"
if [ -z "${DEFAULT_DEVICE}" ] && [ -f "${BOARD_DIR}/boot.env" ]; then
	DEFAULT_DEVICE="$(grep '^DEFAULT_DEVICE=' "${BOARD_DIR}/boot.env" | head -1 | cut -d= -f2- | tr -d '"' || true)"
fi

if [ -n "${DEFAULT_DEVICE}" ] && [ -f "${USERDATA_STAGE}/.minime/devices/${DEFAULT_DEVICE}" ]; then
	cp -f "${USERDATA_STAGE}/.minime/devices/${DEFAULT_DEVICE}" "${USERDATA_STAGE}/.minime/dtb"
else
	first_dtb="$(ls "${USERDATA_STAGE}/.minime/devices/"*.dtb 2>/dev/null | head -1 || true)"
	if [ -n "${first_dtb}" ]; then
		cp -f "${first_dtb}" "${USERDATA_STAGE}/.minime/dtb"
	fi
fi

# 3. Stage Boot Script (boot.scr)
BOOT_CMD_TEMPLATE="${COMMON_DIR}/boot.cmd"
BOOT_ENV="${BOARD_DIR}/boot.env"
if [ -f "${BOOT_CMD_TEMPLATE}" ] && [ -f "${BOOT_ENV}" ]; then
	BOOTARGS=""
	EXTRA_ENV=""
	# shellcheck disable=SC1090
	. "${BOOT_ENV}"
	TMP_BOOT_CMD="${WORK_TMP}/boot.cmd"
	sed -e "s|@BOOTARGS@|${BOOTARGS}|g" \
		-e "s|@DEFAULT_DEVICE@|${DEFAULT_DEVICE}|g" \
		-e "s|@EXTRA_ENV@|${EXTRA_ENV}|g" \
		"${BOOT_CMD_TEMPLATE}" >"${TMP_BOOT_CMD}"
	mkimage -C none -A arm -T script -d "${TMP_BOOT_CMD}" "${USERDATA_STAGE}/boot.scr"
fi

# 4. Stage DT Overlays
OVERLAY_SRC_DIR="${BOARD_DIR}/dtbo"
if [ -d "${OVERLAY_SRC_DIR}" ] && command -v dtc >/dev/null 2>&1; then
	mkdir -p "${USERDATA_STAGE}/.minime/overlays"
	for dts_file in "${OVERLAY_SRC_DIR}"/*.dts; do
		[ -f "${dts_file}" ] || continue
		dtbo_name="$(basename "${dts_file}" .dts).dtbo"
		dtc -@ -I dts -O dtb -o "${USERDATA_STAGE}/.minime/overlays/${dtbo_name}" "${dts_file}"
	done
fi

# 5. Device Config & Triggers
if [ -x "${COMMON_DIR}/scripts/device.sh" ]; then
	"${COMMON_DIR}/scripts/device.sh" init-cfg "${USERDATA_STAGE}/.minime/config/device.cfg"
fi

if [ -f "${BOARD_DIR}/first-boot-probe.sh" ]; then
	touch "${USERDATA_STAGE}/.minime/config/first_boot_probe"
fi
touch "${USERDATA_STAGE}/.minime/config/first_boot_expand"

# 6. Stage UI Payload
if [ -d "${INPUT_DIR}/ui" ]; then
	cp -rp "${INPUT_DIR}/ui/." "${USERDATA_STAGE}/"
fi

# 7. Stage Bootloaders
if [ "${BOARD}" = "h700" ]; then
	[ -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl.bin" ] && cp -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl.bin" "${BINARIES_DIR}/"
	[ -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl-ddr3.bin" ] && cp -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl-ddr3.bin" "${USERDATA_STAGE}/.minime/u-boot-ddr3.bin"
else
	[ -f "${UBOOT_OUT_DIR}/idbloader.img" ] && cp -f "${UBOOT_OUT_DIR}/idbloader.img" "${BINARIES_DIR}/"
	[ -f "${UBOOT_OUT_DIR}/u-boot.itb" ] && cp -f "${UBOOT_OUT_DIR}/u-boot.itb" "${BINARIES_DIR}/"
fi

# 8. Create FAT32 Partition Image (userdata.vfat)
STAGE_MB="$(du -sm "${USERDATA_STAGE}" | cut -f1)"
VFAT_MB=$((STAGE_MB + 256))
[ "$VFAT_MB" -lt 1040 ] && VFAT_MB=1040
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count="${VFAT_MB}" status=none
mkdosfs -F 32 -s 32 -n minime "${BINARIES_DIR}/userdata.vfat" 536870912

MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/boot.scr" ::boot.scr
for item in .minime .system .ui .tmp_update; do
	if [ -d "${USERDATA_STAGE}/${item}" ] || [ -f "${USERDATA_STAGE}/${item}" ]; then
		MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${USERDATA_STAGE}/${item}" ::
		MTOOLS_SKIP_CHECK=1 mattrib -i "${BINARIES_DIR}/userdata.vfat" +h "::${item}"
	fi
done

for item in "${USERDATA_STAGE}"/*; do
	[ -e "${item}" ] || continue
	b_item="$(basename "${item}")"
	[ "${b_item}" = "boot.scr" ] && continue
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${item}" ::
done

# 9. Invoke genimage
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
[ -f "${GENIMAGE_CFG}" ] || GENIMAGE_CFG="${COMMON_DIR}/genimage.cfg"

IMG_TAG="minime-${TARGET}-${BOARD}"
FINAL_IMG="${OUTPUT_DIR}/${IMG_TAG}.img"
FINAL_IMG_XZ="${FINAL_IMG}.xz"

rm -f "${FINAL_IMG}" "${FINAL_IMG_XZ}"

cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i "s/__IMAGE_NAME__/${IMG_TAG}.img/g" "${ROOTPATH_TMP}/genimage.cfg"

genimage \
	--rootpath "${ROOTPATH_TMP}" \
	--tmppath "${WORK_TMP}/genimage.tmp" \
	--inputpath "${BINARIES_DIR}" \
	--outputpath "${OUTPUT_DIR}" \
	--config "${ROOTPATH_TMP}/genimage.cfg"

if [ ! -f "${FINAL_IMG}" ]; then
	echo "ERROR: Image output missing: ${FINAL_IMG}" >&2
	exit 1
fi

echo "Compressing ${FINAL_IMG}..."
xz -f -T2 "${FINAL_IMG}"
echo "Build complete: ${FINAL_IMG_XZ}"
