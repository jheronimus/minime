#!/bin/sh
# Board-specific post-build hook for RK3566.
# Installs board overlay (e.g. userspace thermal watchdog) into the target.
# Canonical source: alpine/board/rk3566/overlay/ (shared with Alpine).

set -eu

ALPINE_BOARD="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/rk3566/overlay"
if [ -d "${ALPINE_BOARD}" ]; then
	cp -a "${ALPINE_BOARD}/." "${TARGET_DIR}/"
fi
