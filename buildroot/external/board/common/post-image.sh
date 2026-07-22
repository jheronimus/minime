#!/bin/sh
# shellcheck shell=sh
# Forward Buildroot post-image invocation to shared alpine/board/common/post-image.sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MINIME_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
exec "${MINIME_ROOT}/alpine/board/common/post-image.sh" -d buildroot "$@"
