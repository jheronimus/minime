#!/bin/sh
# shellcheck shell=sh
# Minime Update Package Generator
#
# Usage:
#   mkupdate.sh --target <alpine|buildroot> --board <h700|rk3326|rk3566> \
#                 --input-dir <dir> --output-dir <dir>

set -eu

usage() {
	echo "Usage: ${0##*/} --target <alpine|buildroot> --board <h700|rk3326|rk3566> --input-dir <dir> --output-dir <dir>" >&2
	exit 1
}

TARGET=""
BOARD=""
INPUT_DIR=""
OUTPUT_DIR=""

UI=""

while [ $# -gt 0 ]; do
	case "$1" in
	--target)
		TARGET="$2"
		shift 2
		;;
	--board)
		BOARD="$2"
		shift 2
		;;
	--ui)
		UI="$2"
		shift 2
		;;
	--input-dir)
		INPUT_DIR="$2"
		shift 2
		;;
	--output-dir)
		OUTPUT_DIR="$2"
		shift 2
		;;
	*)
		usage
		;;
	esac
done

if [ -z "$TARGET" ] || [ -z "$BOARD" ] || [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
	usage
fi

mkdir -p "${OUTPUT_DIR}"

WORK_TMP="$(mktemp -d)"
cleanup() {
	rm -rf "${WORK_TMP}"
}
trap cleanup EXIT

STAGE_DIR="${WORK_TMP}/update"
mkdir -p "${STAGE_DIR}/devices"

[ -f "${INPUT_DIR}/Image" ] || { echo "ERROR: Image missing" >&2; exit 1; }
[ -f "${INPUT_DIR}/initramfs.img" ] || { echo "ERROR: initramfs.img missing" >&2; exit 1; }
[ -f "${INPUT_DIR}/system.erofs" ] || { echo "ERROR: system.erofs missing" >&2; exit 1; }

cp -f "${INPUT_DIR}/Image" "${STAGE_DIR}/kernel"
cp -f "${INPUT_DIR}/initramfs.img" "${STAGE_DIR}/initramfs"
cp -f "${INPUT_DIR}/system.erofs" "${STAGE_DIR}/system"

if [ -d "${INPUT_DIR}/devices" ]; then
	cp -f "${INPUT_DIR}/devices/"*.dtb "${STAGE_DIR}/devices/" 2>/dev/null || true
fi
cp -f "${INPUT_DIR}"/*.dtb "${STAGE_DIR}/devices/" 2>/dev/null || true

# Generate manifest
cat <<EOF >"${STAGE_DIR}/manifest.json"
{
  "target": "${TARGET}",
  "board": "${BOARD}",
  "ui": "${UI}",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF

if [ -n "${UI}" ]; then
	UPDATE_PKG="${OUTPUT_DIR}/minime-${TARGET}-${BOARD}-${UI}.tar.xz"
else
	UPDATE_PKG="${OUTPUT_DIR}/minime-${TARGET}-${BOARD}.tar.xz"
fi
(cd "${STAGE_DIR}" && tar -cf - . | xz -T0 -9 > "${UPDATE_PKG}")

echo "Update package created: ${UPDATE_PKG}"
