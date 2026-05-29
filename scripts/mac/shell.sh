#!/bin/bash

set -euo pipefail

ORB_MACHINE="${ORB_MACHINE:-builder}"
ORB_USER="${ORB_USER:-$(id -un)}"
LINUX_ROOT="${LINUX_ROOT:-/mnt/mac$(pwd)}"
SCRIPT_DIR="$(dirname "$0")"

# Ensure the VM is prepared and running
"$SCRIPT_DIR/prepare_vm.sh"

# Open shell inside VM
orb -m "$ORB_MACHINE" -u "$ORB_USER" -w "$LINUX_ROOT" sh
