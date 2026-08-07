#!/bin/bash
# Check the target device's running build against the latest testing OTA.
# Usage: ./scripts/check-version.sh <os> <board> <ui> [ip]
#
# The device's installed commit is read from /mnt/sdcard/.minime/manifest.json
# (written by mkupdate.sh). The "latest build" is the current testing-release
# OTA for the target, fetched on demand via fetch-asset.sh.
# Prints whether the device is up to date; exits 0 if so, 1 if out of date.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="${1:-}"
BOARD="${2:-}"
UI="${3:-}"
TARGET_IP="${4:-}"

if [ -z "$OS" ] || [ -z "$BOARD" ] || [ -z "$UI" ]; then
	echo "ERROR: check-version requires <os> <board> <ui>." >&2
	echo "Usage: $0 <os> <board> <ui> [ip]" >&2
	exit 1
fi

if [ -z "$TARGET_IP" ]; then
	if [ -f "deploy.cfg" ]; then
		TARGET_IP=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
	fi
fi

if [ -z "$TARGET_IP" ]; then
	echo "ERROR: No target IP specified and target_ip not found in deploy.cfg." >&2
	echo "Usage: $0 <os> <board> <ui> [ip]" >&2
	exit 1
fi

ota=$("$SCRIPT_DIR/fetch-asset.sh" "minime-${OS}-${BOARD}-${UI}.tar.zst")

latest_commit=$(tar -xOf "${ota}" ./.minime/manifest.json 2>/dev/null | sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' | head -n1 || true)
if [ -z "$latest_commit" ]; then
	echo "ERROR: '${ota}' has no .minime/manifest.json (stale OTA, re-fetch)." >&2
	exit 1
fi

device_manifest=$("$SCRIPT_DIR/remote-cmd.sh" "cat /mnt/sdcard/.minime/manifest.json 2>/dev/null || true" "$TARGET_IP" || true)
device_commit=$(echo "$device_manifest" | sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' | head -n1)

if [ -z "$device_commit" ]; then
	echo "The device has no .minime/manifest.json (installed before build-identity manifests). Running commit is unknown; latest build is ${latest_commit}." >&2
	exit 1
fi

if [ "$device_commit" = "$latest_commit" ]; then
	echo "The device is up to date, running commit ${device_commit}"
	exit 0
else
	echo "The device is out of date: running commit ${device_commit}, the latest build is ${latest_commit}"
	exit 1
fi
