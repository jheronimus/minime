#!/bin/sh
# shellcheck shell=sh
# Stage 04: Stage bootloader blobs, run genimage, and compress output image

set -eu

# Stage prebuilt bootloader blobs from alpine/bootloader/<soc>/ into BINARIES_DIR
BL_DIR="${MINIME_SOURCE_ROOT}/bootloader/${SOC_NAME}"
if [ "${SOC_NAME}" = "h700" ]; then
	BL_BIN="${BL_DIR}/u-boot-sunxi-with-spl.bin"
	if [ -f "${BL_BIN}" ]; then
		cp -f "${BL_BIN}" "${BINARIES_DIR}/u-boot-sunxi-with-spl.bin"
	fi
	# Stage DDR3 variant for runtime swap on LPDDR3 devices
	BL_DDR3="${BL_DIR}/u-boot-sunxi-with-spl-ddr3.bin"
	if [ -f "${BL_DDR3}" ]; then
		cp -f "${BL_DDR3}" "${BINARIES_DIR}/u-boot-sunxi-with-spl-ddr3.bin"
	fi
else
	BL_IDB="${BL_DIR}/idbloader.img"
	BL_ITB="${BL_DIR}/u-boot.itb"
	if [ -f "${BL_IDB}" ] && [ -f "${BL_ITB}" ]; then
		cp -f "${BL_IDB}" "${BINARIES_DIR}/idbloader.img"
		cp -f "${BL_ITB}" "${BINARIES_DIR}/u-boot.itb"
	fi
fi

# Fallback: Copy idbloader.img from U-Boot build directory if missing in BINARIES_DIR
if [ ! -f "${BINARIES_DIR}/idbloader.img" ]; then
	echo "Checking for idbloader.img in U-Boot build directory..."
	for uboot_dir in "${BUILD_DIR}"/uboot-*; do
		if [ -f "${uboot_dir}/idbloader.img" ]; then
			echo "Found idbloader.img in ${uboot_dir}, copying to ${BINARIES_DIR}..."
			cp -f "${uboot_dir}/idbloader.img" "${BINARIES_DIR}/idbloader.img"
			break
		fi
	done
fi

echo "Running genimage..."
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"
IMG_TAG="minime${DISTRO_SUFFIX}-${SOC_NAME}"
FINAL_IMG="${BINARIES_DIR}/${IMG_TAG}.img"
FINAL_IMG_XZ="${FINAL_IMG}.xz"

rm -rf "${GENIMAGE_TMP}"
rm -f "${FINAL_IMG}" "${FINAL_IMG_XZ}"

cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i "s/__IMAGE_NAME__/${IMG_TAG}.img/g" "${ROOTPATH_TMP}/genimage.cfg"

genimage \
	--rootpath "${ROOTPATH_TMP}" \
	--tmppath "${GENIMAGE_TMP}" \
	--inputpath "${BINARIES_DIR}" \
	--outputpath "${BINARIES_DIR}" \
	--config "${ROOTPATH_TMP}/genimage.cfg"

if [ ! -f "${FINAL_IMG}" ]; then
	echo "ERROR: expected image not found: ${FINAL_IMG}" >&2
	exit 1
fi

echo "Compressing final image..."
xz -f -T2 "${FINAL_IMG}"
echo "Image produced: ${FINAL_IMG_XZ}"
