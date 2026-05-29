#!/bin/bash

set -euo pipefail

OS="$(uname -s)"
CMD="$1"

if [ "$OS" = "Darwin" ]; then
    # Run inside OrbStack VM
    # Read environment variables passed from Makefile
    ORB_MACHINE="${ORB_MACHINE:-builder}"
    ORB_USER="${ORB_USER:-$(id -un)}"
    LINUX_ROOT="${LINUX_ROOT:-/mnt/mac$(pwd)}"
    BUILDROOT_DIR="${BUILDROOT_DIR:-buildroot}"

    orb -m "$ORB_MACHINE" -u "$ORB_USER" -w "$LINUX_ROOT/$BUILDROOT_DIR" sh -lc "$CMD"
else
    # Run locally on Linux
    BUILDROOT_DIR="${BUILDROOT_DIR:-buildroot}"
    cd "$BUILDROOT_DIR"
    eval "$CMD"
fi
