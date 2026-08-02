#!/bin/sh
# Download a specific testing-release asset to downloads/.
# Usage: ./scripts/fetch-asset.sh <asset-name>
# Prints the local path on success; exits non-zero if the asset is missing.

set -eu

ASSET="${1:-}"
if [ -z "$ASSET" ]; then
	echo "Usage: $0 <asset-name>" >&2
	exit 1
fi

URL="https://github.com/jheronimus/minime/releases/download/testing/${ASSET}"
DEST="downloads/${ASSET}"

mkdir -p downloads
rm -f "${DEST}"

if command -v aria2c >/dev/null 2>&1; then
	echo "Fetching ${ASSET} using aria2 (10 parallel connections)..." >&2
	if ! aria2c -x10 -s10 -k1m --console-log-level=warn --summary-interval=0 --allow-overwrite=true -d downloads -o "${ASSET}" "${URL}" >/dev/null 2>&1; then
		echo "ERROR: Failed to download ${ASSET} (HTTP error)." >&2
		rm -f "${DEST}"
		exit 1
	fi
else
	echo "Fetching ${ASSET}..." >&2
	curl -L --fail --show-error --progress-bar "${URL}" -o "${DEST}"
fi

echo "Saved to ${DEST}" >&2
echo "${DEST}"
