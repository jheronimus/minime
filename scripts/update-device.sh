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
"$SCRIPT_DIR/remote-cmd.sh" "/etc/init.d/ui stop; killall -9 minui minui.elf minarch minarch.elf keymon keymon.elf 2>/dev/null || true" "$TARGET_IP" >/dev/null 2>&1 || true

echo "2. Uploading update archive over FTP..."
"$SCRIPT_DIR/remote-upload.sh" "$PKG_PATH" "minime-ota.tar.xz" "$TARGET_IP"

echo "3. Applying update on target..."
"$SCRIPT_DIR/remote-cmd.sh" "cd /mnt/sdcard && rm -rf .system && tar -xf minime-ota.tar.xz && rm -f minime-ota.tar.xz && sync" "$TARGET_IP"

echo "4. Triggering system reboot on target..."
"$SCRIPT_DIR/remote-cmd.sh" "sync && reboot" "$TARGET_IP" >/dev/null 2>&1 || true

echo "OTA update successfully delivered to $TARGET_IP!"
