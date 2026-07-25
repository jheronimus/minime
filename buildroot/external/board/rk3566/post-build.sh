#!/bin/sh
# Board-specific post-build hook for RK3566.
# Installs board overlay (e.g. userspace thermal watchdog) into the target.
# Canonical source: alpine/board/rk3566/overlay/ (shared with Alpine).

set -eu

ALPINE_BOARD="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/rk3566/overlay"
if [ -d "${ALPINE_BOARD}" ]; then
	cp -a "${ALPINE_BOARD}/." "${TARGET_DIR}/"
fi

# Install shared thermal-watchdog script.
ALPINE_SCRIPTS="${BR2_EXTERNAL_MINIME_PATH}/../../alpine/board/common/scripts"
mkdir -p "${TARGET_DIR}/usr/share/minime/scripts"
install -m 0755 "${ALPINE_SCRIPTS}/thermal-watchdog" "${TARGET_DIR}/usr/share/minime/scripts/"
