#!/bin/sh
# shellcheck shell=sh
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
	if mountpoint -q /mnt/card 2>/dev/null || grep -q "/mnt/card" /proc/mounts 2>/dev/null; then
		echo "[INITRAMFS $(date -u +'%T' 2>/dev/null || date 2>/dev/null || true)] $*" >> /mnt/card/boot.log 2>/dev/null || true
		sync 2>/dev/null || true
	fi
}

mkdir -p /mnt/card

# Wait for Linux to enumerate SD/eMMC devices.
log_console "Waiting for block devices..."
for _i in 1 2 3 4 5 6 7 8 9 10; do
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

if ! mountpoint -q /mnt/card 2>/dev/null && ! grep -q "/mnt/card" /proc/mounts 2>/dev/null; then
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
