#!/bin/sh
# Fetch a diagnostics bundle from the target device.
#  1. Runs collect-diagnostics.sh on the device to build a tarball.
#  2. Pulls it over FTP (ftpd serves /mnt/sdcard).
# Usage: ./scripts/get-logs.sh [ip]

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IP="${1:-}"

if [ -z "$IP" ] && [ -f "deploy.cfg" ]; then
	IP=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
fi

if [ -z "$IP" ]; then
	echo "ERROR: No target IP specified and target_ip not found in deploy.cfg." >&2
	exit 1
fi

echo "Running diagnostics collector on $IP..."
COLLECT_OUT="$("$SCRIPT_DIR/remote-cmd.sh" "/usr/share/minime/scripts/collect-diagnostics.sh" "$IP")"

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
