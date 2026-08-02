#!/bin/bash
# Network OTA Update Delivery Script for Minime target devices.
# Usage: ./scripts/update-device.sh <package> <ip>

set -euo pipefail

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

python3 - "$TARGET_IP" "$PKG_PATH" <<'EOF'
import ftplib, socket, sys, time

ip = sys.argv[1]
pkg_path = sys.argv[2]

def run_telnet(cmd):
    s = socket.socket()
    s.settimeout(15)
    s.connect((ip, 23))
    time.sleep(0.5)
    s.recv(4096)
    s.sendall(cmd.encode() + b"\n")
    time.sleep(2.0)
    res = s.recv(65536).decode(errors="ignore")
    s.close()
    return res

print("1. Stopping UI service on target...")
run_telnet("/etc/init.d/ui stop; killall -9 minui minui.elf minarch minarch.elf keymon keymon.elf 2>/dev/null || true")

print("2. Uploading update archive over FTP...")
ftp = ftplib.FTP()
ftp.connect(ip, 21)
ftp.login("root", "")
with open(pkg_path, "rb") as f:
    ftp.storbinary("STOR minui-ota.zip", f)
ftp.quit()

print("3. Extracting OTA update archive on target...")
print(run_telnet("cd /mnt/sdcard && unzip -o minui-ota.zip && unzip -o MinUI.zip -d /mnt/sdcard/ 2>/dev/null || true; rm -f minui-ota.zip /mnt/sdcard/.system/minime/.system 2>/dev/null || true"))

print("4. Triggering system reboot on target...")
try:
    run_telnet("sync && reboot")
except Exception:
    pass
EOF

echo "OTA update successfully delivered to $TARGET_IP!"
