#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"
SCRIPT_DIR="$(dirname "$0")"

if ! orb list --running --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
    "$SCRIPT_DIR/prepare.sh"
fi
