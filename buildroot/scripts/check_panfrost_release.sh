#!/bin/sh
set -eu

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
PANFROST_MK="${WORKSPACE}/external/package/panfrost/panfrost.mk"

if [ ! -f "${PANFROST_MK}" ]; then
	echo "ERROR: panfrost.mk not found at ${PANFROST_MK}" >&2
	exit 1
fi

PANFROST_VER="$(grep "^PANFROST_VERSION =" "${PANFROST_MK}" | cut -d' ' -f3)"
DL_DIR="${1:-/buildroot-output/dl}"

if [ ! -d "/buildroot-output" ] && [ "${DL_DIR}" = "/buildroot-output/dl" ]; then
	DL_DIR="${HOME}/.buildroot-dl"
fi

LOCAL_FILE="${DL_DIR}/panfrost/panfrost-${PANFROST_VER}.tar.gz"
if [ -f "${LOCAL_FILE}" ]; then
	echo "Found local Panfrost prebuilt archive: ${LOCAL_FILE}"
	exit 0
fi

URL="https://github.com/jheronimus/minime/releases/download/panfrost-v${PANFROST_VER}/panfrost-${PANFROST_VER}.tar.gz"
echo "Checking Panfrost prebuilt archive: ${URL}"

HTTP_STATUS="$(curl -sIL -o /dev/null -w "%{http_code}" --connect-timeout 5 "${URL}" || echo "000")"
if [ "${HTTP_STATUS}" = "200" ]; then
	echo "Found remote Panfrost prebuilt archive."
	exit 0
fi

echo "ERROR: Panfrost prebuilt archive ${PANFROST_VER} not found in local downloads cache or GitHub Releases (HTTP ${HTTP_STATUS})." >&2
echo "Run 'make panfrost BOARD=h700', upload out/panfrost-${PANFROST_VER}.tar.gz to release panfrost-v${PANFROST_VER}, or place it at:" >&2
echo "  ${LOCAL_FILE}" >&2
exit 1
