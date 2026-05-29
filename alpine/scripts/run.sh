#!/bin/bash

set -euo pipefail

OS="$(uname -s)"
SCRIPT_DIR="$(dirname "$0")"
CMD="$1"

if [ "$OS" = "Darwin" ]; then
    "$SCRIPT_DIR/mac/run.sh" "$CMD"
else
    "$SCRIPT_DIR/linux/run.sh" "$CMD"
fi
