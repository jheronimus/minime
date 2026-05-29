#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"

if command -v orb >/dev/null 2>&1 && orb list --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
    echo "Deleting OrbStack VM '$ORB_MACHINE'..."
    orb delete "$ORB_MACHINE"
fi
