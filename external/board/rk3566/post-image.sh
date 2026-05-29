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
FINAL_IMG="${BINARIES_DIR}/minime-rk3566.img"
FINAL_IMG_GZ="${FINAL_IMG}.gz"

trap "rm -rf \"${ROOTPATH_TMP}\"" EXIT

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
mkdir -p "${USERDATA_STAGE}/.system/config"
mkdir -p "${USERDATA_STAGE}/.system/devices"

# Prepopulate simplified wifi.cfg from template
if [ -f "${SYSTEM_STAGE}/etc/wifi.config.template" ]; then
	cp -f "${SYSTEM_STAGE}/etc/wifi.config.template" "${USERDATA_STAGE}/.system/config/wifi.cfg"
fi

# Prepopulate fallback device.cfg
echo "device=rk3566-anbernic-rg-arc-d.dtb" > "${USERDATA_STAGE}/.system/config/device.cfg"

# Create the first boot expansion trigger file
touch "${USERDATA_STAGE}/.system/config/first_boot_expand"

# Copy main erofs system image
cp -f "${BINARIES_DIR}/system.erofs" "${USERDATA_STAGE}/.system/system.erofs"

# Copy kernel and U-Boot script directly to partition root
cp -f "${BINARIES_DIR}/Image" "${USERDATA_STAGE}/Image"
cp -f "${BINARIES_DIR}/boot.scr" "${USERDATA_STAGE}/boot.scr"

# Copy all platform DTB files to .system/devices
for dtb_file in "${BINARIES_DIR}"/rk356*-anbernic-*.dtb; do
	if [ -f "${dtb_file}" ]; then
		cp -f "${dtb_file}" "${USERDATA_STAGE}/.system/devices/$(basename "${dtb_file}")"
	fi
done

# Assemble custom boot-stage initrd
echo "Assembling custom boot-stage loop-mount initrd..."
INITRD_STAGE="${ROOTPATH_TMP}/initrd"
mkdir -p "${INITRD_STAGE}/bin" "${INITRD_STAGE}/sbin" "${INITRD_STAGE}/lib" "${INITRD_STAGE}/proc" "${INITRD_STAGE}/sys" "${INITRD_STAGE}/dev" "${INITRD_STAGE}/mnt/card" "${INITRD_STAGE}/mnt/system"

# Copy BusyBox binary from target rootfs and create links
cp -f "${SYSTEM_STAGE}/bin/busybox" "${INITRD_STAGE}/bin/busybox"
ln -sf busybox "${INITRD_STAGE}/bin/sh"
ln -sf busybox "${INITRD_STAGE}/bin/mount"
ln -sf busybox "${INITRD_STAGE}/bin/umount"
ln -sf busybox "${INITRD_STAGE}/bin/sleep"
ln -sf busybox "${INITRD_STAGE}/bin/reboot"
ln -sf busybox "${INITRD_STAGE}/sbin/switch_root"

# Copy target shared libraries to support dynamic BusyBox linkage
# Copy ONLY the core runtime linker and standard C libraries to keep initrd extremely small
for lib_pattern in "ld-*.so*" "libc.so*" "libc-*.so" "libm.so*" "libm-*.so" "libresolv.so*" "librt.so*" "libpthread.so*"; do
	find "${SYSTEM_STAGE}/lib" -name "${lib_pattern}" -exec cp -d -a {} "${INITRD_STAGE}/lib/" \; 2>/dev/null || true
	if [ -d "${SYSTEM_STAGE}/lib64" ]; then
		mkdir -p "${INITRD_STAGE}/lib64"
		find "${SYSTEM_STAGE}/lib64" -name "${lib_pattern}" -exec cp -d -a {} "${INITRD_STAGE}/lib64/" \; 2>/dev/null || true
	fi
done


# Write the Custom init script
cat << 'EOF' > "${INITRD_STAGE}/init"
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "Minime Boot Stage 1: Initializing SD Card..."

# Wait for SD card block device
for i in 1 2 3 4 5; do
	[ -b /dev/mmcblk0p1 ] && break
	sleep 1
done

if [ ! -b /dev/mmcblk0p1 ]; then
	echo "ERROR: SD card partition /dev/mmcblk0p1 not found!"
	exec sh
fi

echo "Minime Boot Stage 1: Mounting SD Card (MINIME)..."
mkdir -p /mnt/card
if ! mount -t vfat /dev/mmcblk0p1 /mnt/card; then
	echo "ERROR: Failed to mount SD card!"
	exec sh
fi

# FIRST BOOT EXPANSION CHECK
if [ -f /mnt/card/.system/config/first_boot_expand ]; then
	echo "--------------------------------------------------------"
	echo "      MINIME: PERFORMING FIRST BOOT SD CARD EXPANSION"
	echo "--------------------------------------------------------"
	# Mount card read-write
	mount -o remount,rw /mnt/card
	
	echo "Backing up boot assets to RAM..."
	mkdir -p /tmp/backup
	cp -a /mnt/card/.system /tmp/backup/
	cp -f /mnt/card/Image /tmp/backup/
	cp -f /mnt/card/boot.scr /tmp/backup/
	
	echo "Unmounting card..."
	umount /mnt/card
	
	echo "Re-writing partition table to full disk size..."
	# Re-create partition 1 to span the full size
	printf "d\nn\np\n1\n8192\n\nt\nc\na\nw\n" | fdisk /dev/mmcblk0
	sleep 1
	
	echo "Formatting expanded FAT32 partition..."
	mkfs.vfat -F 32 -n MINIME /dev/mmcblk0p1
	
	echo "Restoring boot assets from RAM..."
	mount -t vfat /dev/mmcblk0p1 /mnt/card
	cp -a /tmp/backup/.system /mnt/card/
	cp -f /tmp/backup/Image /mnt/card/
	cp -f /tmp/backup/boot.scr /mnt/card/
	
	# Delete first_boot_expand in restored filesystem to prevent loop expansion
	rm -f /mnt/card/.system/config/first_boot_expand
	
	echo "SD Card expansion complete! Rebooting..."
	umount /mnt/card
	reboot -f
fi

echo "Minime Boot Stage 1: Loop-mounting rootfs..."
mkdir -p /mnt/system
if ! mount -t erofs -o loop,ro /mnt/card/.system/system.erofs /mnt/system; then
	echo "ERROR: Failed to loop-mount /mnt/card/.system/system.erofs!"
	exec sh
fi

# Move virtual mounts and SD card mount to the new rootfs
mount -o move /sys /mnt/system/sys
mount -o move /proc /mnt/system/proc
mount -o move /dev /mnt/system/dev
mount -o move /mnt/card /mnt/system/mnt/sdcard

echo "Minime Boot Stage 1: Transitioning to Stage 2..."
exec switch_root /mnt/system /sbin/init
EOF
chmod +x "${INITRD_STAGE}/init"

# Compile initrd.img
(cd "${INITRD_STAGE}" && find . | cpio -H newc -o | gzip -9 > "${BINARIES_DIR}/initrd.img")

# Copy initrd.img to USERDATA_STAGE
cp -f "${BINARIES_DIR}/initrd.img" "${USERDATA_STAGE}/.system/initrd.img"

echo "Generating userdata.vfat (Ultra-minimal 80MB partition)..."
rm -f "${BINARIES_DIR}/userdata.vfat"
dd if=/dev/zero of="${BINARIES_DIR}/userdata.vfat" bs=1M count=80
mkdosfs -F 32 -n MINIME "${BINARIES_DIR}/userdata.vfat"


# Populate userdata.vfat recursively using mtools
MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/Image" ::Image
MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" "${USERDATA_STAGE}/boot.scr" ::boot.scr
MTOOLS_SKIP_CHECK=1 mcopy -i "${BINARIES_DIR}/userdata.vfat" -s "${USERDATA_STAGE}/.system" ::

echo "Running genimage..."
rm -rf "${GENIMAGE_TMP}"
rm -f "${FINAL_IMG}" "${FINAL_IMG_GZ}"

cp -f "${GENIMAGE_CFG}" "${ROOTPATH_TMP}/genimage.cfg"
sed -i 's/sp-rk3566.img/minime-rk3566.img/g' "${ROOTPATH_TMP}/genimage.cfg"

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
