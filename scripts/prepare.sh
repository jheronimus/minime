#!/bin/bash

set -euo pipefail

OS="$(uname -s)"
SCRIPT_DIR="$(dirname "$0")"

if [ "$OS" = "Darwin" ]; then
    "$SCRIPT_DIR/mac/prepare.sh"
elif [ "$OS" = "Linux" ]; then
    "$SCRIPT_DIR/linux/prepare.sh"
else
    echo "ERROR: Unsupported OS '$OS'" >&2
    exit 1
fi
