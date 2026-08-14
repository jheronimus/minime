#!/bin/sh
# Fetch a diagnostics bundle from the target device.
#  1. Runs collect-diagnostics.sh on the device (via telnet) to build a tarball.
#  2. Pulls it over FTP (device runs ftpd serving /mnt/sdcard).
# Usage: ./scripts/get-logs.sh [ip]

set -eu

IP="${1:-}"

if [ -z "$IP" ]; then
	if [ -f "deploy.cfg" ]; then
		IP=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
	fi
fi

if [ -z "$IP" ]; then
	echo "ERROR: No target IP address specified and target_ip not found in deploy.cfg." >&2
	exit 1
fi

echo "Running diagnostics collector on $IP..."

COLLECT_OUT=$(
	python3 - "$IP" <<'EOF'
import socket, sys, time

ip = sys.argv[1]
cmd = "/usr/share/minime/scripts/collect-diagnostics.sh"

s = socket.socket()
s.settimeout(30)
s.connect((ip, 23))
time.sleep(0.5)
s.recv(4096)
s.sendall((cmd + "\n").encode())
time.sleep(8)
out = s.recv(65536).decode(errors="ignore")
s.close()

lines = out.splitlines()
if lines and (lines[0].strip() == cmd or cmd in lines[0]):
    lines = lines[1:]
print("\n".join(lines).strip())
EOF
)

REMOTE_FILE=$(echo "$COLLECT_OUT" | grep -oE 'minime-diagnostics-[0-9]+\.tar\.gz' | head -n1 || true)

if [ -z "$REMOTE_FILE" ]; then
	echo "ERROR: could not determine diagnostics file from device output:" >&2
	echo "$COLLECT_OUT" >&2
	exit 1
fi

mkdir -p downloads
LOCAL="downloads/${REMOTE_FILE}"
echo "Pulling ftp://${IP}/${REMOTE_FILE} -> ${LOCAL}"
curl -s -S -u root: -o "$LOCAL" "ftp://${IP}/${REMOTE_FILE}"

if [ ! -s "$LOCAL" ]; then
	echo "ERROR: download produced an empty file." >&2
	rm -f "$LOCAL"
	exit 1
fi

echo "Diagnostics saved to ${LOCAL}"
