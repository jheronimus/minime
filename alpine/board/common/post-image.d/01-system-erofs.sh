#!/bin/sh
# shellcheck shell=sh
# Stage 01: Extract rootfs tar and build system.erofs

set -eu

echo "Generating system.erofs..."
SYSTEM_STAGE="${ROOTPATH_TMP}/system"
mkdir -p "${SYSTEM_STAGE}"

# Extract rootfs.tar to SYSTEM_STAGE
tar -xf "${BINARIES_DIR}/rootfs.tar" -C "${SYSTEM_STAGE}"

# Set file timestamps to epoch 0 for reproducible build
find "${SYSTEM_STAGE}" -exec touch -d @0 {} + 2>/dev/null || true

# Build system.erofs
rm -f "${BINARIES_DIR}/system.erofs"
mkfs.erofs -T 0 -zlz4 "${BINARIES_DIR}/system.erofs" "${SYSTEM_STAGE}"
