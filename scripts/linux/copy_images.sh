#!/bin/bash

set -euo pipefail

BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-$HOME/buildroot-output}"

mkdir -p out
echo "Copying built firmware images to out/..."
mkdir -p "$BUILDROOT_OUTPUT_DIR/images"
cp -r "$BUILDROOT_OUTPUT_DIR/images/"* "out/" 2>/dev/null || true
