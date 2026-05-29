#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"
ORB_USER="${ORB_USER:-$(id -un)}"
LINUX_ROOT="${LINUX_ROOT:-/mnt/mac$(pwd)}"
BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-/home/$ORB_USER/buildroot-output}"

mkdir -p out
echo "Copying built firmware images to out/..."

orb -m "$ORB_MACHINE" -u "$ORB_USER" sh -lc "
    mkdir -p '$BUILDROOT_OUTPUT_DIR/images' && \
    cp -r '$BUILDROOT_OUTPUT_DIR/images/'* '$LINUX_ROOT/out/' 2>/dev/null || true
"
