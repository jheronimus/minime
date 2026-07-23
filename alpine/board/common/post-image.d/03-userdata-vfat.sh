#!/bin/sh
# shellcheck shell=sh
# Stage 03: Prepare FAT32 partition files and generate userdata.vfat

set -eu

echo "Preparing single FAT32 partition filesystem staging..."
USERDATA_STAGE="${ROOTPATH_TMP}/userdata"
mkdir -p "${USERDATA_STAGE}/.minime/config"
mkdir -p "${USERDATA_STAGE}/.minime/devices"
mkdir -p "${USERDATA_STAGE}/.system" "${USERDATA_STAGE}/.userdata"

# Create standard roms, bios, and saves folders on SD card root.
mkdir -p "${USERDATA_STAGE}/Roms"
mkdir -p "${USERDATA_STAGE}/Bios"
mkdir -p "${USERDATA_STAGE}/Saves"

# Prepopulate self-documenting device.cfg via shared device.sh script
"${MINIME_SOURCE_ROOT}/board/common/scripts/device.sh" init-cfg "${USERDATA_STAGE}/.minime/config/device.cfg"

# Compile and stage device-tree overlays (e.g. RK3566 CPU undervolt DTBOs)
OVERLAY_SRC_DIR="${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/overlays"
if [ -d "${OVERLAY_SRC_DIR}" ]; then
	echo "Compiling DT overlays for ${SOC_NAME}..."
	mkdir -p "${USERDATA_STAGE}/.minime/overlays"
	for dts_file in "${OVERLAY_SRC_DIR}"/*.dts; do
		[ -f "${dts_file}" ] || continue
		dtbo_name="$(basename "${dts_file}" .dts).dtbo"
		"${HOST_DIR}/bin/dtc" -@ -I dts -O dtb -o \
			"${USERDATA_STAGE}/.minime/overlays/${dtbo_name}" "${dts_file}"
	done
fi

# Create the first boot trigger files
if [ -f "${BOARD_DIR}/first-boot-probe.sh" ]; then
	touch "${USERDATA_STAGE}/.minime/config/first_boot_probe"
fi
touch "${USERDATA_STAGE}/.minime/config/first_boot_expand"

# Copy main erofs system image and initramfs
cp -f "${BINARIES_DIR}/system.erofs" "${USERDATA_STAGE}/.minime/system"
cp -f "${BINARIES_DIR}/initramfs" "${USERDATA_STAGE}/.minime/initramfs"

# Copy kernel and U-Boot script
cp -f "${BINARIES_DIR}/Image" "${USERDATA_STAGE}/.minime/kernel"
cp -f "${BINARIES_DIR}/boot.scr" "${USERDATA_STAGE}/boot.scr"

# Copy DDR3 U-Boot binary for H700 runtime swap (initramfs detects DDR type
# via AXP DCDC3 voltage and replaces the default DDR4 binary if needed).
if [ "${SOC_NAME}" = "h700" ] && [ -f "${BINARIES_DIR}/u-boot-sunxi-with-spl-ddr3.bin" ]; then
	cp -f "${BINARIES_DIR}/u-boot-sunxi-with-spl-ddr3.bin" "${USERDATA_STAGE}/.minime/u-boot-ddr3.bin"
fi

# Copy each platform DTB once.
for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
	if [ -f "${dtb_file}" ]; then
		dtb_basename="$(basename "${dtb_file}")"
		cp -f "${dtb_file}" "${USERDATA_STAGE}/.minime/devices/${dtb_basename}"
	fi
done

# Copy the default DTB to a flat path for U-Boot (avoids nested directory issues).
# Read DEFAULT_DEVICE from boot.env; fall back to first available DTB if the
# grep fails (e.g. path resolution issues inside the build container).
DEFAULT_DEVICE=""
_BOOT_ENV="${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/boot.env"
if [ -f "${_BOOT_ENV}" ]; then
	DEFAULT_DEVICE="$(grep '^DEFAULT_DEVICE=' "${_BOOT_ENV}" | head -1 | cut -d= -f2- | tr -d '"' || true)"
fi
_DTB_SRC=""
if [ -n "${DEFAULT_DEVICE}" ] && [ -f "${USERDATA_STAGE}/.minime/devices/${DEFAULT_DEVICE}" ]; then
	_DTB_SRC="${USERDATA_STAGE}/.minime/devices/${DEFAULT_DEVICE}"
else
	# Fallback: pick the first available DTB from the devices directory.
	_DTB_SRC="$(ls "${USERDATA_STAGE}/.minime/devices/"*.dtb 2>/dev/null | head -1 || true)"
fi
if [ -n "${_DTB_SRC}" ] && [ -f "${_DTB_SRC}" ]; then
	cp -f "${_DTB_SRC}" "${USERDATA_STAGE}/.minime/dtb"
	echo "Staged default DTB as .minime/dtb: $(basename "${_DTB_SRC}")"
else
	echo "WARNING: No DTB available to stage as .minime/dtb" >&2
fi

# Copy UI files from the generic staging directory (if any)
if [ -d "${BINARIES_DIR}/ui" ]; then
	echo "Staging UI files onto SD card partition..."
	cp -rp "${BINARIES_DIR}/ui/." "${USERDATA_STAGE}/"
fi

echo "Generating userdata.vfat..."
rm -f "${BINARIES_DIR}/userdata.vfat"
STAGE_MB="$(du -sm "${USERDATA_STAGE}" | cut -f1)"
VFAT_MB=$((STAGE_MB + 384))
[ "$VFAT_MB" -lt 1040 ] && VFAT_MB=1040
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count="${VFAT_MB}"
mkdosfs -F 32 -s 32 -n minime "${BINARIES_DIR}/userdata.vfat"

# Populate userdata.vfat: copy a 128MB dummy file first to reserve low clusters (Cluster 2..8193)
# for first-boot FAT table expansion, then copy system files.
mkdir -p "${USERDATA_STAGE}/.minime"
dd if=/dev/zero of="${USERDATA_STAGE}/.minime/reserved.bin" bs=1M count=128 2>/dev/null
MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/.minime/reserved.bin" ::.minime/reserved.bin
rm -f "${USERDATA_STAGE}/.minime/reserved.bin"

MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/boot.scr" ::boot.scr
for item in .minime .system .userdata; do
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" \
		-s "${USERDATA_STAGE}/${item}" ::
	MTOOLS_SKIP_CHECK=1 mattrib -i "${BINARIES_DIR}/userdata.vfat" +h "::${item}"
done

# Hide staged DT overlays directory if present.
if [ -d "${USERDATA_STAGE}/.minime/overlays" ]; then
	MTOOLS_SKIP_CHECK=1 mattrib -i "${BINARIES_DIR}/userdata.vfat" +h "::.minime/overlays"
fi

# Copy visible user files and directories.
for item in "${USERDATA_STAGE}"/*; do
	[ -e "${item}" ] || continue
	basename_item="$(basename "${item}")"
	[ "${basename_item}" = "boot.scr" ] && continue
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${item}" ::
done
