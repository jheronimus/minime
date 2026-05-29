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
	usage
	exit 1
fi

GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"
ROOTPATH_TMP="$(mktemp -d)"
FINAL_IMG="${BINARIES_DIR}/minime-h700.img"
FINAL_IMG_GZ="${FINAL_IMG}.gz"

trap "rm -rf \"${ROOTPATH_TMP}\"" EXIT

echo "Generating system.erofs..."
SYSTEM_STAGE="${ROOTPATH_TMP}/system"
mkdir -p "${SYSTEM_STAGE}"

# Extract Buildroot's rootfs.tar to SYSTEM_STAGE
tar -xf "${BINARIES_DIR}/rootfs.tar" -C "${SYSTEM_STAGE}"

# Copy kernel boot assets directly to root of SYSTEM_STAGE
for boot_file in Image sun50i-h700-anbernic-rg35xx-sp.dtb boot.scr; do
	if [ ! -f "${BINARIES_DIR}/${boot_file}" ]; then
		echo "ERROR: missing boot image file: ${BINARIES_DIR}/${boot_file}" >&2
		exit 1
	fi
	cp -f "${BINARIES_DIR}/${boot_file}" "${SYSTEM_STAGE}/"
done

# Copy all other compiled H700 device tree binary files
copied_dtb_count=0
for dtb_file in "${BINARIES_DIR}"/sun50i-h700-anbernic-*.dtb; do
	if [ -f "${dtb_file}" ] && [ "$(basename "${dtb_file}")" != "sun50i-h700-anbernic-rg35xx-sp.dtb" ]; then
		cp -f "${dtb_file}" "${SYSTEM_STAGE}/"
		copied_dtb_count=$((copied_dtb_count + 1))
	fi
done

echo "Successfully copied core assets and ${copied_dtb_count} additional H700 device tree binaries."

# Set file timestamps to epoch 0 for reproducible build
find "${SYSTEM_STAGE}" -exec touch -d @0 {} + 2>/dev/null || true

# Build system.erofs
rm -f "${BINARIES_DIR}/system.erofs"
mkfs.erofs -T 0 -zlz4 "${BINARIES_DIR}/system.erofs" "${SYSTEM_STAGE}"

echo "Generating userdata.vfat..."
USERDATA_STAGE="${ROOTPATH_TMP}/userdata"
mkdir -p "${USERDATA_STAGE}/.sp/config/wifi"

# Prepopulate wifi template config
if [ -f "${SYSTEM_STAGE}/etc/wifi.config.template" ]; then
	cp -f "${SYSTEM_STAGE}/etc/wifi.config.template" "${USERDATA_STAGE}/.sp/config/wifi/wifi.config"
fi

# Create a 100MB FAT32 filesystem for userdata
rm -f "${BINARIES_DIR}/userdata.vfat"
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count=100
mkdosfs -F 32 -n SDCARD "${BINARIES_DIR}/userdata.vfat"

# Use mtools to populate VFAT userdata seed folders to avoid mounting (which requires sudo)
MTOOLS_SKIP_CHECK=1 mmd -i "${BINARIES_DIR}/userdata.vfat" ::.sp || true
MTOOLS_SKIP_CHECK=1 mmd -i "${BINARIES_DIR}/userdata.vfat" ::.sp/config || true
MTOOLS_SKIP_CHECK=1 mmd -i "${BINARIES_DIR}/userdata.vfat" ::.sp/config/wifi || true
if [ -f "${USERDATA_STAGE}/.sp/config/wifi/wifi.config" ]; then
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/.sp/config/wifi/wifi.config" ::.sp/config/wifi/wifi.config || true
fi

echo "Running genimage..."
rm -rf "${GENIMAGE_TMP}"
rm -f "${FINAL_IMG}" "${FINAL_IMG_GZ}"

# Copy genimage config file to a temp location and make sure the filenames inside match
cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i 's/sp-h700.img/minime-h700.img/g' "${ROOTPATH_TMP}/genimage.cfg"

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
gzip -f -9 "${FINAL_IMG}"
echo "Image produced: ${FINAL_IMG_GZ}"
