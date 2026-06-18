#!/bin/sh
# Board-specific post-build hook for RK3566.
# Installs the board overlay (e.g. userspace thermal watchdog) into the target.

set -eu

cp -a "${BOARD_DIR}/overlay/." "${TARGET_DIR}/"
