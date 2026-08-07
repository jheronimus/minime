#!/bin/bash
# Network OTA Update Delivery Script for Minime target devices.
# Usage: ./scripts/update-device.sh <package> <ip>
#
# The package is a Minime OTA archive whose layout mirrors the SD card:
#   .minime/{kernel,initramfs,system,devices/*.dtb,ui.env,manifest.json}
#   .system/{minime,res,version.txt,commits.txt}
# Deliberately scoped: user data (Bios/, Roms/, Saves/, .userdata/, .minime/config)
# is never in the archive and is never touched.
#
# Delivery semantics:
#   - .system/  : clean-replaced (rm -rf then extract) — pure UI payload, avoids stale files
#   - .minime/  : overlaid (tar -xf) — device state (config/, traits, dtb) preserved

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_PATH="${1:-}"
TARGET_IP="${2:-}"

if [ -z "$PKG_PATH" ] || [ -z "$TARGET_IP" ]; then
	echo "Usage: $0 <package> <ip>" >&2
	exit 1
fi

if [ ! -f "$PKG_PATH" ]; then
	echo "ERROR: Package file '$PKG_PATH' not found." >&2
	exit 1
fi

echo "Delivering OTA update '$PKG_PATH' to device at $TARGET_IP..."

echo "1. Stopping UI service on target..."
"$SCRIPT_DIR/remote-cmd.sh" "/etc/init.d/ui stop; killall -9 minui.elf minarch.elf keymon.elf 2>/dev/null || true" "$TARGET_IP" >/dev/null 2>&1 || true

echo "2. Uploading update archive over FTP..."
"$SCRIPT_DIR/remote-upload.sh" "$PKG_PATH" "minime-ota.tar.zst" "$TARGET_IP"

echo "3. Applying update on target..."
# Decompress with unzstd (busybox tar's -J is xz, not zstd) piped into tar.
# Run in the background and log: decompressing the ~100 MB archive outlives
# the telnet session window, so extract, verify, then reboot via a marker.
"$SCRIPT_DIR/remote-cmd.sh" "cd /mnt/sdcard && rm -f minime-ota.tar.zst.minime-ok && rm -rf .system && (unzstd -c minime-ota.tar.zst | tar -xf - > /tmp/ota-extract.log 2>&1 && touch minime-ota.tar.zst.minime-ok; echo done >> /tmp/ota-extract.log) & echo applying" "$TARGET_IP" >/dev/null 2>&1 || true

echo "4. Waiting for extraction to complete..."
applied="no"
attempt=0
while [ "$attempt" -lt 60 ]; do
	sleep 5
	attempt=$((attempt + 1))
	applied=$("$SCRIPT_DIR/remote-cmd.sh" "test -f /mnt/sdcard/minime-ota.tar.zst.minime-ok && echo yes || echo no" "$TARGET_IP" 2>/dev/null | tr -d '\r' | tail -n1)
	if [ "$applied" = "yes" ]; then
		break
	fi
done

if [ "$applied" != "yes" ]; then
	echo "ERROR: OTA extraction did not complete in time." >&2
	echo "Check /tmp/ota-extract.log on the device." >&2
	exit 1
fi

echo "5. Cleaning up and rebooting..."
"$SCRIPT_DIR/remote-cmd.sh" "rm -f /mnt/sdcard/minime-ota.tar.zst.minime-ok && rm -f /mnt/sdcard/minime-ota.tar.zst && sync && reboot" "$TARGET_IP" >/dev/null 2>&1 || true

echo "OTA update successfully delivered to $TARGET_IP!"
