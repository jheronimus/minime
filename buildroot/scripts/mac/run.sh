#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"
ORB_USER="${ORB_USER:-$(id -un)}"
LINUX_ROOT="${LINUX_ROOT:-/mnt/mac$(pwd)}"
BUILDROOT_DIR="${BUILDROOT_DIR:-buildroot}"
CMD="$1"

orb -m "$ORB_MACHINE" -u "$ORB_USER" -w "$LINUX_ROOT/$BUILDROOT_DIR" sh -lc "$CMD"
