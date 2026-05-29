#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"
ORB_USER="${ORB_USER:-$(id -un)}"
BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-/home/$ORB_USER/buildroot-output}"

# Clean host-side build artifacts
rm -rf buildroot logs out

# Clean VM native output directory if the VM is running
if command -v orb >/dev/null 2>&1 && orb list --running --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
    echo "Cleaning VM native output directory..."
    orb -m "$ORB_MACHINE" -u "$ORB_USER" sh -c "rm -rf '$BUILDROOT_OUTPUT_DIR'" || true
fi
