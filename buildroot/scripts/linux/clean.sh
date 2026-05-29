#!/bin/bash

set -euo pipefail

BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-$HOME/buildroot-output}"

echo "Cleaning local build directories..."
rm -rf buildroot logs out

echo "Cleaning local buildroot output directory..."
rm -rf "$BUILDROOT_OUTPUT_DIR"
