#!/bin/bash

set -euo pipefail

BUILDROOT_DIR="${BUILDROOT_DIR:-buildroot}"
CMD="$1"

cd "$BUILDROOT_DIR"
eval "$CMD"
