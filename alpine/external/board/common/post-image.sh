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

BOARD_DIR="$(dirname "$GENIMAGE_CFG")"
SOC_NAME="$(basename "$BOARD_DIR")"

if [ ! -f "${BOARD_DIR}/board.env" ]; then
	echo "ERROR: ${BOARD_DIR}/board.env is missing!" >&2
	exit 1
fi

. "${BOARD_DIR}/board.env"

if [ -z "${DEFAULT_DTB:-}" ] || [ -z "${DTB_PATTERN:-}" ] || [ -z "${GENIMAGE_IMAGE_NAME:-}" ]; then
	echo "ERROR: board.env must define DEFAULT_DTB, DTB_PATTERN, and GENIMAGE_IMAGE_NAME!" >&2
	exit 1
fi

GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"
ROOTPATH_TMP="$(mktemp -d)"
FINAL_IMG="${BINARIES_DIR}/minime-${SOC_NAME}.img"
FINAL_IMG_GZ="${FINAL_IMG}.gz"

cleanup() {
	rm -rf "${ROOTPATH_TMP}"
}
trap cleanup EXIT

echo "Generating system.erofs..."
SYSTEM_STAGE="${ROOTPATH_TMP}/system"
mkdir -p "${SYSTEM_STAGE}"

# Extract Buildroot's rootfs.tar to SYSTEM_STAGE
tar -xf "${BINARIES_DIR}/rootfs.tar" -C "${SYSTEM_STAGE}"

# Set file timestamps to epoch 0 for reproducible build
find "${SYSTEM_STAGE}" -exec touch -d @0 {} + 2>/dev/null || true

# Build system.erofs
rm -f "${BINARIES_DIR}/system.erofs"
mkfs.erofs -T 0 -zlz4 "${BINARIES_DIR}/system.erofs" "${SYSTEM_STAGE}"

# Stage the FAT32 boot partition files
echo "Preparing single FAT32 partition filesystem staging..."
USERDATA_STAGE="${ROOTPATH_TMP}/userdata"
mkdir -p "${USERDATA_STAGE}/.minime/config"
mkdir -p "${USERDATA_STAGE}/.minime/devices"
mkdir -p "${USERDATA_STAGE}/.ui" "${USERDATA_STAGE}/.ui/config"
mkdir -p "${USERDATA_STAGE}/.cores" "${USERDATA_STAGE}/.cores/config"

# Create standard roms, bios, and saves folder structure on SD card root
mkdir -p "${USERDATA_STAGE}/roms"
mkdir -p "${USERDATA_STAGE}/bios"
mkdir -p "${USERDATA_STAGE}/saves"

for system in gb gbc gba nes snes md gg sms pce psx ss; do
	mkdir -p "${USERDATA_STAGE}/roms/${system}"
	mkdir -p "${USERDATA_STAGE}/saves/${system}"
done

# Commented out systems (no emulators shipped yet):
# for system in lynx ngp vb pkm pico8 wswan mduck watara; do
# 	mkdir -p "${USERDATA_STAGE}/roms/${system}"
# 	mkdir -p "${USERDATA_STAGE}/saves/${system}"
# done

# Prepopulate simplified wifi.cfg from template
if [ -f "${SYSTEM_STAGE}/etc/wifi.config.template" ]; then
	cp -f "${SYSTEM_STAGE}/etc/wifi.config.template" "${USERDATA_STAGE}/.minime/config/wifi.cfg"
fi

# Prepopulate core mapping contract
cp -f "${BR2_EXTERNAL_MINIME_PATH}/board/common/config/cores.cfg" \
	"${USERDATA_STAGE}/.minime/config/cores.cfg"

# Prepopulate self-documenting device.cfg
DEVICE_CFG="${USERDATA_STAGE}/.minime/config/device.cfg"
cat << 'EOF' > "${DEVICE_CFG}"
# minime Device Configuration
#
EOF

if [ "${AUTODETECT_SUPPORTED:-}" = "y" ]; then
	cat << 'EOF' >> "${DEVICE_CFG}"
# By default, this is set to 'auto' to automatically detect your device.
# If autodetection fails or you need to force a specific device/screen panel revision,
# uncomment and set 'device' to one of the built-in options listed below.
#
# Supported device options:
EOF
	for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
		if [ -f "${dtb_file}" ]; then
			echo "# - $(basename "${dtb_file}")" >> "${DEVICE_CFG}"
		fi
	done
	cat << 'EOF' >> "${DEVICE_CFG}"
#
device=auto
EOF
else
	cat << 'EOF' >> "${DEVICE_CFG}"
# Autodetection is not supported on this platform.
# You must set 'device' to one of the built-in options listed below
# matching your specific handheld device.
#
# Supported device options:
EOF
	for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
		if [ -f "${dtb_file}" ]; then
			echo "# - $(basename "${dtb_file}")" >> "${DEVICE_CFG}"
		fi
	done
	cat << EOF >> "${DEVICE_CFG}"
#
device=${DEFAULT_DTB}
EOF
fi


# Create the first boot trigger files
if [ -f "${BOARD_DIR}/first-boot-probe.sh" ]; then
	touch "${USERDATA_STAGE}/.minime/config/first_boot_probe"
fi
touch "${USERDATA_STAGE}/.minime/config/first_boot_expand"

# Copy main erofs system image
cp -f "${BINARIES_DIR}/system.erofs" "${USERDATA_STAGE}/.minime/system"

# Copy kernel and U-Boot script
if [ "${MINIME_USE_ROCKNIX_KERNEL:-n}" = "y" ] && [ "${SOC_NAME}" = "rk3566" ] && [ -f "${BOARD_DIR}/prebuilt/rocknix-20260601/rocknix-kernel" ]; then
	echo "Using ROCKNIX RK3566 kernel for test image..."
	cp -f "${BOARD_DIR}/prebuilt/rocknix-20260601/rocknix-kernel" "${USERDATA_STAGE}/.minime/kernel"
else
	cp -f "${BINARIES_DIR}/Image" "${USERDATA_STAGE}/.minime/kernel"
fi
cp -f "${BINARIES_DIR}/boot.scr" "${USERDATA_STAGE}/boot.scr"

# Copy each platform DTB once.
for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
	if [ -f "${dtb_file}" ]; then
		dtb_basename="$(basename "${dtb_file}")"
		cp -f "${dtb_file}" "${USERDATA_STAGE}/.minime/devices/${dtb_basename}"
	fi
done


# Copy UI files from the generic staging directory (if any)
if [ -d "${BINARIES_DIR}/ui" ]; then
	echo "Staging UI files onto SD card partition..."
	cp -rp "${BINARIES_DIR}/ui/." "${USERDATA_STAGE}/"
fi


# Assemble custom boot-stage initrd
echo "Assembling custom boot-stage loop-mount initrd..."
INITRD_STAGE="${ROOTPATH_TMP}/initrd"
mkdir -p "${INITRD_STAGE}/bin" "${INITRD_STAGE}/sbin" "${INITRD_STAGE}/lib" \
	"${INITRD_STAGE}/proc" "${INITRD_STAGE}/sys" "${INITRD_STAGE}/dev" \
	"${INITRD_STAGE}/tmp" "${INITRD_STAGE}/mnt/card" "${INITRD_STAGE}/mnt/system"
for lib_dir in lib32 lib64 usr/lib32 usr/lib64; do
	[ -L "${SYSTEM_STAGE}/${lib_dir}" ] || continue
	mkdir -p "${INITRD_STAGE}/$(dirname "${lib_dir}")"
	cp -P "${SYSTEM_STAGE}/${lib_dir}" "${INITRD_STAGE}/${lib_dir}"
done

# Copy BusyBox binary from target rootfs and create links
cp -f "${SYSTEM_STAGE}/bin/busybox" "${INITRD_STAGE}/bin/busybox"
# Shell & basic utilities
ln -sf busybox "${INITRD_STAGE}/bin/sh"
ln -sf busybox "${INITRD_STAGE}/bin/mount"
ln -sf busybox "${INITRD_STAGE}/bin/mountpoint"
ln -sf busybox "${INITRD_STAGE}/bin/umount"
ln -sf busybox "${INITRD_STAGE}/bin/sleep"
ln -sf busybox "${INITRD_STAGE}/bin/reboot"
ln -sf busybox "${INITRD_STAGE}/bin/cp"
ln -sf busybox "${INITRD_STAGE}/bin/mkdir"
ln -sf busybox "${INITRD_STAGE}/bin/rm"
ln -sf busybox "${INITRD_STAGE}/bin/cat"
ln -sf busybox "${INITRD_STAGE}/bin/echo"
ln -sf busybox "${INITRD_STAGE}/bin/sync"
ln -sf ../bin/busybox "${INITRD_STAGE}/sbin/switch_root"

copy_runtime_lib() {
	lib_name="$1"
	lib_source="$(find "${SYSTEM_STAGE}/lib" "${SYSTEM_STAGE}/usr/lib" \
		-name "${lib_name}" -print -quit)"
	[ -n "${lib_source}" ] || {
		echo "ERROR: initramfs dependency ${lib_name} is missing" >&2
		exit 1
	}
	lib_target="${INITRD_STAGE}${lib_source#"${SYSTEM_STAGE}"}"
	[ -e "${lib_target}" ] && return
	mkdir -p "$(dirname "${lib_target}")"
	cp -Lf "${lib_source}" "${lib_target}"
	for dependency in $("${HOST_DIR}/bin/patchelf" --print-needed "${lib_source}"); do
		copy_runtime_lib "${dependency}"
	done
}

copy_runtime_binary() {
	binary_name="$1"
	binary_source="${SYSTEM_STAGE}/usr/sbin/${binary_name}"
	cp -f "${binary_source}" "${INITRD_STAGE}/sbin/${binary_name}"
	for dependency in $("${HOST_DIR}/bin/patchelf" --print-needed "${binary_source}"); do
		copy_runtime_lib "${dependency}"
	done
	interpreter="$("${HOST_DIR}/bin/patchelf" --print-interpreter "${binary_source}")"
	mkdir -p "${INITRD_STAGE}$(dirname "${interpreter}")"
	cp -Lf "${SYSTEM_STAGE}${interpreter}" "${INITRD_STAGE}${interpreter}"
}

copy_runtime_binary parted
copy_runtime_binary fatresize


# Write the Custom init script
cat << 'EOF' > "${INITRD_STAGE}/init"
#!/bin/sh
export PATH=/bin:/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

CARD_DEV=""

log_console() {
	echo "$*"
}

log_card() {
	echo "$*"
}

# Wait for Linux to enumerate SD/eMMC devices.
for i in 1 2 3 4 5 6 7 8 9 10; do
	for dev in /dev/mmcblk*p1; do
		[ -b "$dev" ] && CARD_DEV="$dev" && break
	done
	[ -n "$CARD_DEV" ] && break
	sleep 1
done

if [ -z "$CARD_DEV" ]; then
	log_console "ERROR: no /dev/mmcblk*p1 block devices found"
	exec sh
fi

mkdir -p /mnt/card
for dev in /dev/mmcblk*p1; do
	[ -b "$dev" ] || continue
	if mount -t vfat "$dev" /mnt/card; then
		if [ -f /mnt/card/.minime/system ]; then
			CARD_DEV="$dev"
			break
		fi
		umount /mnt/card
	fi
done

if ! mountpoint -q /mnt/card; then
	log_console "ERROR: failed to mount a MINIME FAT partition"
	exec sh
fi

# First-boot hardware probe.
if [ -f /mnt/card/.minime/config/first_boot_probe ]; then
	mount -o remount,rw /mnt/card

	if [ -f /sbin/first-boot-probe.sh ]; then
		sh /sbin/first-boot-probe.sh
	fi

	rm -f /mnt/card/.minime/config/first_boot_probe
	umount /mnt/card
	reboot -f
fi

# Grow partition 1 and FAT32 without reformatting.
if [ -f /mnt/card/.minime/config/first_boot_expand ]; then
	log_console "Expanding SD card..."
	umount /mnt/card
	DISK_DEV="${CARD_DEV%p1}"
	if ! parted -s -f "$DISK_DEV" resizepart 1 100%; then
		log_console "ERROR: failed to expand partition 1 on $DISK_DEV"
		exec sh
	fi
	sleep 1
	if ! fatresize -q -f -s max "$CARD_DEV"; then
		log_console "ERROR: failed to expand $CARD_DEV"
		exec sh
	fi
	mount -t vfat "$CARD_DEV" /mnt/card
	rm -f /mnt/card/.minime/config/first_boot_expand
fi

mkdir -p /mnt/system
if ! mount -t erofs -o loop,ro /mnt/card/.minime/system /mnt/system; then
	log_card "ERROR: failed to mount /mnt/card/.minime/system"
	exec sh
fi

# Also ensure backlight is at a visible level.  minui later reads
# msettings.bin, but having backlight off at boot makes the display
# invisible until userspace takes over.
for bl in /sys/class/backlight/*/brightness; do
	[ -w "$bl" ] && echo 5 > "$bl" 2>/dev/null || true
done

# Hard check that target init exists and is executable before switch_root
if [ ! -x /mnt/system/sbin/init ]; then
	log_card "ERROR: /mnt/system/sbin/init is missing or not executable"
	ls -la /mnt/system/sbin/init 2>&1 || true
	exec sh
fi

# Move virtual mounts and SD card mount to the new rootfs
mount -o move /sys /mnt/system/sys
mount -o move /proc /mnt/system/proc
mount -o move /dev /mnt/system/dev
mount -o move /mnt/card /mnt/system/mnt/sdcard

exec switch_root /mnt/system /sbin/init
EOF
chmod +x "${INITRD_STAGE}/init"

# Copy optional board-specific first boot probe script if it exists
if [ -f "${BOARD_DIR}/first-boot-probe.sh" ]; then
	cp -f "${BOARD_DIR}/first-boot-probe.sh" "${INITRD_STAGE}/sbin/first-boot-probe.sh"
	chmod +x "${INITRD_STAGE}/sbin/first-boot-probe.sh"
fi


# Compile the uncompressed initramfs CPIO archive.
(cd "${INITRD_STAGE}" && find . | cpio -H newc -o > "${BINARIES_DIR}/initramfs")

# Copy initramfs to USERDATA_STAGE
cp -f "${BINARIES_DIR}/initramfs" "${USERDATA_STAGE}/.minime/initramfs"

echo "Generating userdata.vfat..."
rm -f "${BINARIES_DIR}/userdata.vfat"
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count=1040
mkdosfs -F 32 -s 32 -n minime "${BINARIES_DIR}/userdata.vfat"


# Populate userdata.vfat recursively using mtools.
MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/boot.scr" ::boot.scr
for item in .minime .ui .cores; do
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" \
		-s "${USERDATA_STAGE}/${item}" ::
	MTOOLS_SKIP_CHECK=1 mattrib -i "${BINARIES_DIR}/userdata.vfat" +h "::${item}"
done

# Copy visible user files and directories.
for item in "${USERDATA_STAGE}"/*; do
	[ -e "${item}" ] || continue
	basename_item="$(basename "${item}")"
	[ "${basename_item}" = "boot.scr" ] && continue
	MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${item}" ::
done

# Copy idbloader.img from U-Boot build directory if it exists and is missing in BINARIES_DIR
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
rm -rf "${GENIMAGE_TMP}"
rm -f "${FINAL_IMG}" "${FINAL_IMG_GZ}"

cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i "s/${GENIMAGE_IMAGE_NAME}/minime-${SOC_NAME}.img/g" "${ROOTPATH_TMP}/genimage.cfg"

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
