#!/bin/bash
# Network OTA Update Delivery Script for Minime target devices.
# Usage: ./scripts/update-device.sh <package> <ip>

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
python3 - "$TARGET_IP" "$PKG_PATH" <<'EOF'
import ftplib, sys

ip = sys.argv[1]
pkg_path = sys.argv[2]

ftp = ftplib.FTP()
ftp.connect(ip, 21)
ftp.login("root", "")
with open(pkg_path, "rb") as f:
    ftp.storbinary("STOR minui-ota.zip", f)
ftp.quit()
EOF

echo "3. Extracting OTA update archive on target..."
"$SCRIPT_DIR/remote-cmd.sh" "cd /mnt/sdcard && unzip -o minui-ota.zip && unzip -o MinUI.zip -d /mnt/sdcard/ 2>/dev/null || true; rm -f minui-ota.zip /mnt/sdcard/.system/minime/.system 2>/dev/null || true" "$TARGET_IP"

echo "4. Triggering system reboot on target..."
"$SCRIPT_DIR/remote-cmd.sh" "sync && reboot" "$TARGET_IP" >/dev/null 2>&1 || true

echo "OTA update successfully delivered to $TARGET_IP!"
