#!/bin/sh
# shellcheck shell=sh
# Minime Linear Image & Update Package Builder.
#
# Usage:
#   ./build.sh --target <alpine|buildroot> --board <h700|rk3326|rk3566> \
#              --input-dir <dir> --output-dir <dir> [--ui <minui|allium|muos>] [--include-roms]
set -eu

TARGET="" BOARD="" INPUT_DIR="" OUTPUT_DIR="" UI="minui" INCLUDE_ROMS="${INCLUDE_ROMS:-0}"
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
	--ui)
		UI="$2"
		shift 2
		;;
	--include-roms)
		INCLUDE_ROMS=1
		shift 1
		;;
	--no-roms)
		INCLUDE_ROMS=0
		shift 1
		;;
	*)
		echo "Unknown arg: $1" >&2
		exit 1
		;;
	esac
done

[ -z "$TARGET" ] || [ -z "$BOARD" ] || [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ] && {
	echo "Usage: $0 --target <alpine|buildroot> --board <board> --input-dir <dir> --output-dir <dir> [--ui <ui>] [--include-roms]" >&2
	exit 1
}

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD_DIR="${MINIME_ROOT}/packages/components/boards/${BOARD}"
COMMON_DIR="${MINIME_ROOT}/packages/components/boards/common"
UBOOT_OUT_DIR="${MINIME_ROOT}/packages/bootloader/${BOARD}/out"

WORK_TMP="$(mktemp -d)"
trap 'rm -rf "${WORK_TMP}"' EXIT
STAGE_DIR="${WORK_TMP}/stage"
BINARIES_DIR="${WORK_TMP}/binaries"
ROOTPATH_TMP="${WORK_TMP}/rootpath"
mkdir -p "${OUTPUT_DIR}" "${BINARIES_DIR}" "${ROOTPATH_TMP}" "${STAGE_DIR}/.minime/devices" "${STAGE_DIR}/.minime/config/bluetooth"

# 1. Stage OS payload
for f in Image:kernel initramfs.img:initramfs system.erofs:system; do
	src="${f%%:*}"
	dst="${f##*:}"
	[ -f "${INPUT_DIR}/${src}" ] || {
		echo "ERROR: ${src} missing in ${INPUT_DIR}" >&2
		exit 1
	}
	cp -f "${INPUT_DIR}/${src}" "${STAGE_DIR}/.minime/${dst}"
done
[ -d "${INPUT_DIR}/devices" ] && cp -f "${INPUT_DIR}/devices/"*.dtb "${STAGE_DIR}/.minime/devices/" 2>/dev/null || true
cp -f "${INPUT_DIR}"/*.dtb "${STAGE_DIR}/.minime/devices/" 2>/dev/null || true

DEFAULT_DEVICE="${DEFAULT_DEVICE:-}"
[ -z "${DEFAULT_DEVICE}" ] && [ -f "${BOARD_DIR}/boot.env" ] && DEFAULT_DEVICE="$(grep '^DEFAULT_DEVICE=' "${BOARD_DIR}/boot.env" | head -1 | cut -d= -f2- | tr -d '"' || true)"
if [ -n "${DEFAULT_DEVICE}" ] && [ -f "${STAGE_DIR}/.minime/devices/${DEFAULT_DEVICE}" ]; then
	cp -f "${STAGE_DIR}/.minime/devices/${DEFAULT_DEVICE}" "${STAGE_DIR}/.minime/dtb"
else
	first_dtb="$(ls "${STAGE_DIR}/.minime/devices/"*.dtb 2>/dev/null | head -1 || true)"
	[ -n "${first_dtb}" ] && cp -f "${first_dtb}" "${STAGE_DIR}/.minime/dtb"
fi

# 2. Stage UI payload & preloaded ROMs
case "${TARGET}" in
alpine | musl) LIBC="musl" ;;
buildroot | glibc) LIBC="glibc" ;;
*) LIBC="musl" ;;
esac

UI_ART_DIR="${MINIME_ROOT}/packages/ui/out"
if [ "$UI" != "none" ]; then
	local_tar="${UI_ART_DIR}/${UI}-${LIBC}-aarch64.tar.zst"
	local_zip="${UI_ART_DIR}/${UI}-${LIBC}-aarch64.zip"
	if [ -f "${local_tar}" ]; then
		unzstd -q -c "${local_tar}" | tar -xf - -C "${STAGE_DIR}"
	elif [ -f "${local_zip}" ]; then
		unzip -q -o "${local_zip}" -d "${STAGE_DIR}"
	elif [ -d "${INPUT_DIR}/ui-${UI}" ]; then
		cp -rp "${INPUT_DIR}/ui-${UI}/." "${STAGE_DIR}/"
	else
		echo "ERROR: UI artifact for ${UI} (${LIBC}) not found in ${UI_ART_DIR}" >&2
		exit 1
	fi
	if [ "$UI" = "minui" ]; then
		for z in "${STAGE_DIR}/MinUI.zip" "${STAGE_DIR}/MinUI-extras.zip"; do
			[ -f "$z" ] && unzip -q -o "$z" -d "${STAGE_DIR}" && rm -f "$z" || true
		done
	fi
fi

case "${INCLUDE_ROMS}" in
1 | true | TRUE | yes | YES)
	if [ -f "${MINIME_ROOT}/roms/install.sh" ]; then
		sh "${MINIME_ROOT}/roms/install.sh" "${STAGE_DIR}"
	fi
	;;
esac

MINIME_COMMIT="${MINIME_COMMIT:-$(git -C "${MINIME_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
UI_COMMIT="${UI_COMMIT:-$(git -C "${MINIME_ROOT}/packages/ui/${UI}" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
cat <<JSON >"${STAGE_DIR}/.minime/manifest.json"
{
  "target": "${TARGET}",
  "board": "${BOARD}",
  "ui": "${UI}",
  "minime_commit": "${MINIME_COMMIT}",
  "ui_commit": "${UI_COMMIT}",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
JSON

# 3. Build Update Package (.tar.zst)
PKG_NAME="minime-${TARGET}-${BOARD}-${UI}"
(cd "${STAGE_DIR}" && tar -cf - . | zstd -q -9 >"${OUTPUT_DIR}/${PKG_NAME}.tar.zst")
echo "Update package created: ${OUTPUT_DIR}/${PKG_NAME}.tar.zst"

# 4. Stage SD boot script & device configs
if [ -f "${COMMON_DIR}/boot.cmd" ] && [ -f "${BOARD_DIR}/boot.env" ]; then
	BOOTARGS=""
	EXTRA_ENV=""
	. "${BOARD_DIR}/boot.env"
	sed -e "s|@BOOTARGS@|${BOOTARGS}|g" -e "s|@DEFAULT_DEVICE@|${DEFAULT_DEVICE}|g" -e "s|@EXTRA_ENV@|${EXTRA_ENV}|g" "${COMMON_DIR}/boot.cmd" >"${WORK_TMP}/boot.cmd"
	mkimage -C none -A arm -T script -d "${WORK_TMP}/boot.cmd" "${STAGE_DIR}/boot.scr"
fi
[ -x "${COMMON_DIR}/scripts/device.sh" ] && "${COMMON_DIR}/scripts/device.sh" init-cfg "${STAGE_DIR}/.minime/config/device.cfg"
[ -f "${BOARD_DIR}/first-boot-probe.sh" ] && touch "${STAGE_DIR}/.minime/config/first_boot_probe"
touch "${STAGE_DIR}/.minime/config/first_boot_expand"
echo 1 >"${STAGE_DIR}/.minime/config/bluetooth/enabled"

# 5. Stage Bootloader Blobs
if [ "${BOARD}" = "h700" ]; then
	cp -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl.bin" "${BINARIES_DIR}/"
	[ -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl-ddr3.bin" ] && cp -f "${UBOOT_OUT_DIR}/u-boot-sunxi-with-spl-ddr3.bin" "${STAGE_DIR}/.minime/u-boot-ddr3.bin"
elif [ "${BOARD}" = "rk3326" ]; then
	for f in idbloader.img uboot.img trust.img; do cp -f "${UBOOT_OUT_DIR}/${f}" "${BINARIES_DIR}/"; done
else
	cp -f "${UBOOT_OUT_DIR}/idbloader.img" "${UBOOT_OUT_DIR}/u-boot.itb" "${BINARIES_DIR}/"
fi

# 6. Format FAT32 userdata & run genimage
STAGE_MB="$(du -sm "${STAGE_DIR}" | cut -f1)"
VFAT_MB=$((STAGE_MB + 256))
[ "$VFAT_MB" -lt 1040 ] && VFAT_MB=1040
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count="${VFAT_MB}" status=none
mkdosfs -F 32 -s 32 -n minime "${BINARIES_DIR}/userdata.vfat"
[ -f "${STAGE_DIR}/boot.scr" ] && MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${STAGE_DIR}/boot.scr" ::boot.scr
for item in .minime .system .ui .allium .muos; do
	[ -e "${STAGE_DIR}/${item}" ] && MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${STAGE_DIR}/${item}" :: && MTOOLS_SKIP_CHECK=1 mattrib -i "${BINARIES_DIR}/userdata.vfat" +h "::${item}" || true
done
for item in "${STAGE_DIR}"/*; do
	[ -e "${item}" ] && [ "$(basename "${item}")" != "boot.scr" ] && MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${item}" :: || true
done

GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
[ -f "${GENIMAGE_CFG}" ] || GENIMAGE_CFG="${COMMON_DIR}/genimage.cfg"
cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i "s/__IMAGE_NAME__/${PKG_NAME}.img/g" "${ROOTPATH_TMP}/genimage.cfg"

genimage --rootpath "${ROOTPATH_TMP}" --tmppath "${WORK_TMP}/genimage.tmp" --inputpath "${BINARIES_DIR}" --outputpath "${OUTPUT_DIR}" --config "${ROOTPATH_TMP}/genimage.cfg"
zstd -q -9 -f "${OUTPUT_DIR}/${PKG_NAME}.img" -o "${OUTPUT_DIR}/${PKG_NAME}.img.zst"
rm -f "${OUTPUT_DIR}/${PKG_NAME}.img"
echo "Image built: ${OUTPUT_DIR}/${PKG_NAME}.img.zst"
