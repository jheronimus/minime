#!/bin/sh
# scripts/check_panfrost_release.sh — Automated fallback for Panfrost prebuilt download.
# Excluded from Git via .gitignore if needed, but since it's a build pipeline tool, it's tracked in Git.

set -eu

# Paths
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
PANFROST_MK="${WORKSPACE}/external/package/panfrost/panfrost.mk"

if [ ! -f "${PANFROST_MK}" ]; then
    echo "ERROR: panfrost.mk not found at ${PANFROST_MK}" >&2
    exit 1
fi

PANFROST_VER=$(grep "PANFROST_VERSION =" "${PANFROST_MK}" | cut -d' ' -f3)

# Resolve downloads directory (handle container vs host paths)
DL_DIR="${1:-/buildroot-output/dl}"
BOARD="${2:-h700}"

# If running on the host (e.g. /buildroot-output doesn't exist) and using podman,
# map the container-internal /buildroot-output/dl to the host cache path ~/.buildroot-dl
if [ ! -d "/buildroot-output" ] && [ "${DL_DIR}" = "/buildroot-output/dl" ]; then
    DL_DIR="${HOME}/.buildroot-dl"
fi

# 1. Check if the file already exists in the local downloads cache
LOCAL_FILE="${DL_DIR}/panfrost/panfrost-${PANFROST_VER}.tar.gz"
if [ -f "${LOCAL_FILE}" ]; then
    echo "Found local prebuilt archive in downloads cache at ${LOCAL_FILE}. Proceeding."
    exit 0
fi

# 2. Check if the release asset exists on GitHub
URL="https://github.com/jheronimus/minime/releases/download/panfrost-v${PANFROST_VER}/panfrost-${PANFROST_VER}.tar.gz"
echo "Checking GitHub Release for ${URL}..."

# Use a silent curl request with a timeout
HTTP_STATUS=$(curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 "${URL}" || echo "000")

if [ "${HTTP_STATUS}" = "200" ]; then
    echo "Release asset exists on GitHub. Buildroot will download it automatically."
    exit 0
fi

echo ""
echo "⚠️  WARNING: Prebuilt archive for version ${PANFROST_VER} not found on GitHub (HTTP ${HTTP_STATUS}) and not in local cache."
echo "Running local bootstrap build to compile it from source..."

# 3. Trigger local compilation
make panfrost BOARD="${BOARD}"

# 4. Copy the compiled tarball to Buildroot downloads folder
mkdir -p "${DL_DIR}/panfrost"
cp -dpfr "${WORKSPACE}/out/panfrost-${PANFROST_VER}.tar.gz" "${LOCAL_FILE}"
echo "Prebuilt archive successfully placed in downloads cache: ${LOCAL_FILE}"
