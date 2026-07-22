#!/bin/sh

set -eu

usage() {
	echo "Usage: ${0##*/} -c GENIMAGE_CONFIG_FILE -b BOARD_DIR [-d alpine] [-o OUTPUT_DIR]" >&2
}

GENIMAGE_CFG=""
BOARD_DIR_OVERRIDE=""
DISTRO="alpine"
OUTPUT_DIR=""

opts="$(getopt -n "${0##*/}" -o b:c:d:o: -- "$@")" || exit $?
eval set -- "$opts"
while true; do
	case "$1" in
	-b)
		BOARD_DIR_OVERRIDE="$2"
		shift 2
		;;
	-c)
		GENIMAGE_CFG="$2"
		shift 2
		;;
	-d)
		DISTRO="$2"
		shift 2
		;;
	-o)
		OUTPUT_DIR="$2"
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

case "${DISTRO}" in
alpine) ;;
*)
	echo "ERROR: -d must be 'alpine'" >&2
	exit 1
	;;
esac

if [ -n "${OUTPUT_DIR}" ]; then
	BINARIES_DIR="${OUTPUT_DIR}"
fi

if [ -n "${BOARD_DIR_OVERRIDE}" ]; then
	BOARD_DIR="${BOARD_DIR_OVERRIDE}"
else
	BOARD_DIR="$(dirname "$GENIMAGE_CFG")"
fi
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
case "${DISTRO}" in
alpine) IMG_TAG="minime-alpine-${SOC_NAME}" ;;
*) IMG_TAG="minime-${SOC_NAME}" ;;
esac
FINAL_IMG="${BINARIES_DIR}/${IMG_TAG}.img"
FINAL_IMG_XZ="${FINAL_IMG}.xz"

cleanup() {
	rm -rf "${ROOTPATH_TMP}"
}
trap cleanup EXIT

echo "Generating system.erofs..."
SYSTEM_STAGE="${ROOTPATH_TMP}/system"
mkdir -p "${SYSTEM_STAGE}"

# Extract rootfs.tar to SYSTEM_STAGE
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
mkdir -p "${USERDATA_STAGE}/.system" "${USERDATA_STAGE}/.userdata"

# Create standard roms, bios, and saves folders on SD card root.
# Each UI bootstraps its own per-system subdirectories.
mkdir -p "${USERDATA_STAGE}/Roms"
mkdir -p "${USERDATA_STAGE}/Bios"
mkdir -p "${USERDATA_STAGE}/Saves"

MINIME_SOURCE_ROOT="${MINIME_SOURCE_ROOT:-}"
[ -n "${MINIME_SOURCE_ROOT}" ] || {
	echo "ERROR: MINIME_SOURCE_ROOT is not set" >&2
	exit 1
}

# Prepopulate self-documenting device.cfg
DEVICE_CFG="${USERDATA_STAGE}/.minime/config/device.cfg"
cat <<'EOF' >"${DEVICE_CFG}"
# minime Device Configuration
#
EOF

if [ "${SOC_NAME}" = "rk3566" ]; then
	cat <<'EOF' >>"${DEVICE_CFG}"
# CPU undervolt (RK3566 only). Lowers CPU core voltage per OPP to reduce
# power and thermals. Opt-in: silicon lottery varies and an unstable
# setting can corrupt data, not just crash.
# Allowed values: off, l1, l2, l3 (l3 is most aggressive).
# Recovery: mount this FAT partition on a PC and set undervolt=off.
# Default off: silicon lottery varies; opt in via the Power settings
# menu or by setting undervolt=l1|l2|l3 below.
undervolt=off
EOF
fi

if [ "${AUTODETECT_SUPPORTED:-}" = "y" ]; then
	cat <<'EOF' >>"${DEVICE_CFG}"
# By default, this is set to 'auto' to automatically detect your device.
# If autodetection fails or you need to force a specific device/screen panel revision,
# uncomment and set 'device' to one of the built-in options listed below.
#
# Supported device options:
EOF
	for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
		if [ -f "${dtb_file}" ]; then
			echo "# - $(basename "${dtb_file}")" >>"${DEVICE_CFG}"
		fi
	done
	cat <<'EOF' >>"${DEVICE_CFG}"
#
device=auto
EOF
else
	cat <<'EOF' >>"${DEVICE_CFG}"
# Autodetection is not supported on this platform.
# You must set 'device' to one of the built-in options listed below
# matching your specific handheld device.
#
# Supported device options:
EOF
	for dtb_file in "${BINARIES_DIR}"/${DTB_PATTERN}; do
		if [ -f "${dtb_file}" ]; then
			echo "# - $(basename "${dtb_file}")" >>"${DEVICE_CFG}"
		fi
	done
	cat <<EOF >>"${DEVICE_CFG}"
#
device=${DEFAULT_DTB}
EOF
fi

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

# Copy main erofs system image
cp -f "${BINARIES_DIR}/system.erofs" "${USERDATA_STAGE}/.minime/system"

# Copy kernel and U-Boot script
cp -f "${BINARIES_DIR}/Image" "${USERDATA_STAGE}/.minime/kernel"
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
	for dependency in $("${HOST_DIR:-/usr}/bin/patchelf" --print-needed "${lib_source}"); do
		copy_runtime_lib "${dependency}"
	done
}

copy_runtime_binary() {
	binary_name="$1"
	binary_source="${SYSTEM_STAGE}/usr/sbin/${binary_name}"
	cp -f "${binary_source}" "${INITRD_STAGE}/sbin/${binary_name}"
	for dependency in $("${HOST_DIR:-/usr}/bin/patchelf" --print-needed "${binary_source}"); do
		copy_runtime_lib "${dependency}"
	done
	interpreter="$("${HOST_DIR:-/usr}/bin/patchelf" --print-interpreter "${binary_source}")"
	mkdir -p "${INITRD_STAGE}$(dirname "${interpreter}")"
	cp -Lf "${SYSTEM_STAGE}${interpreter}" "${INITRD_STAGE}${interpreter}"
}

copy_runtime_binary parted
copy_runtime_binary fatresize

# Write the Custom init script
cat <<'EOF' >"${INITRD_STAGE}/init"
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
	if grep -q " /mnt/card " /proc/mounts 2>/dev/null; then
		echo "[INITRAMFS $(date -u +'%T' 2>/dev/null || date 2>/dev/null || true)] $*" >> /mnt/card/boot.log 2>/dev/null || true
		sync 2>/dev/null || true
	fi
}

mkdir -p /mnt/card

# Wait for Linux to enumerate SD/eMMC devices.
log_console "Waiting for block devices..."
for i in 1 2 3 4 5 6 7 8 9 10; do
	for dev in /dev/mmcblk*p1 /dev/vd*1 /dev/sd*1; do
		[ -b "$dev" ] && CARD_DEV="$dev" && break
	done
	[ -n "$CARD_DEV" ] && break
	sleep 1
done

if [ -z "$CARD_DEV" ]; then
	log_console "ERROR: no /dev/mmcblk*p1, /dev/vd*1, or /dev/sd*1 block devices found"
	exec sh
fi

for dev in /dev/mmcblk*p1 /dev/vd*1 /dev/sd*1; do
	[ -b "$dev" ] || continue
	if mount -t vfat "$dev" /mnt/card 2>/dev/null; then
		if [ -f /mnt/card/.minime/system ]; then
			CARD_DEV="$dev"
			log_card "[INITRAMFS] Mounted MINIME FAT partition on $CARD_DEV"
			break
		fi
		umount /mnt/card 2>/dev/null || true
	fi
done

if ! grep -q " /mnt/card " /proc/mounts 2>/dev/null; then
	log_console "ERROR: failed to mount a MINIME FAT partition"
	exec sh
fi

log_card "[INITRAMFS] Initialized persistent logging on $CARD_DEV"

# First-boot hardware probe.
if [ -f /mnt/card/.minime/config/first_boot_probe ]; then
	log_card "[INITRAMFS] Running first-boot hardware probe..."
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
	log_card "[INITRAMFS] Expanding SD card on $CARD_DEV..."
	umount /mnt/card 2>/dev/null || true
	DISK_DEV="${CARD_DEV%p1}"
	log_card "[INITRAMFS] Running parted on $DISK_DEV..."
	if ! parted -s -f "$DISK_DEV" resizepart 1 100%; then
		mount -t vfat "$CARD_DEV" /mnt/card 2>/dev/null || true
		log_card "ERROR: failed to expand partition 1 on $DISK_DEV"
		exec sh
	fi
	sleep 1
	log_card "[INITRAMFS] Running fatresize on $CARD_DEV..."
	if ! fatresize -q -f -s max "$CARD_DEV"; then
		mount -t vfat "$CARD_DEV" /mnt/card 2>/dev/null || true
		log_card "ERROR: failed to expand $CARD_DEV"
		exec sh
	fi
	mount -t vfat "$CARD_DEV" /mnt/card 2>/dev/null || true
	log_card "[INITRAMFS] Partition expansion successful. Removing first_boot_expand..."
	rm -f /mnt/card/.minime/config/first_boot_expand
	sync
fi

log_card "[INITRAMFS] Mounting EROFS system image..."
mkdir -p /mnt/system
if ! mount -t erofs -o loop,ro /mnt/card/.minime/system /mnt/system; then
	log_card "ERROR: failed to mount /mnt/card/.minime/system"
	exec sh
fi
log_card "[INITRAMFS] EROFS system image mounted successfully."

# Also ensure backlight is at a visible level.  minui later reads
# msettings.bin, but having backlight off at boot makes the display
# invisible until userspace takes over.
for bl in /sys/class/backlight/*/brightness; do
	if [ -w "$bl" ]; then
		echo 5 > "$bl" 2>/dev/null || true
		log_card "[INITRAMFS] Backlight device $bl set to 5"
	fi
done

# Hard check that target init exists and is executable before switch_root
if [ ! -x /mnt/system/sbin/init ]; then
	log_card "ERROR: /mnt/system/sbin/init is missing or not executable"
	ls -la /mnt/system/sbin/init 2>&1 || true
	exec sh
fi

log_card "[INITRAMFS] Moving mounts and switching root to /mnt/system..."
mount -o move /sys /mnt/system/sys
mount -o move /proc /mnt/system/proc
mount -o move /dev /mnt/system/dev
mount -o move /mnt/card /mnt/system/mnt/sdcard

exec switch_root /mnt/system /sbin/init
EOF
chmod +x "${INITRD_STAGE}/init"

# Copy optional board-specific first boot probe script if it exists
if [ -f "${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/first-boot-probe.sh" ]; then
	cp -f "${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/first-boot-probe.sh" "${INITRD_STAGE}/sbin/first-boot-probe.sh"
	chmod +x "${INITRD_STAGE}/sbin/first-boot-probe.sh"
fi

# Compile the initramfs CPIO archive.
(cd "${INITRD_STAGE}" && find . | cpio -H newc -o >"${BINARIES_DIR}/initramfs")

# Copy initramfs to USERDATA_STAGE
cp -f "${BINARIES_DIR}/initramfs" "${USERDATA_STAGE}/.minime/initramfs"

echo "Generating userdata.vfat..."
rm -f "${BINARIES_DIR}/userdata.vfat"
STAGE_MB="$(du -sm "${USERDATA_STAGE}" | cut -f1)"
VFAT_MB=$(( STAGE_MB + 256 ))
[ "$VFAT_MB" -lt 1024 ] && VFAT_MB=1024
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count="${VFAT_MB}"
mkdosfs -F 32 -s 32 -n minime "${BINARIES_DIR}/userdata.vfat"

# Populate userdata.vfat recursively using mtools.
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
