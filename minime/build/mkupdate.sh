#!/bin/sh
# shellcheck shell=sh
# Minime Update Package Generator
#
# Usage:
#   mkupdate.sh --target <alpine|buildroot> --board <h700|rk3326|rk3566> \
#                 --input-dir <dir> --output-dir <dir> [--ui <minui|allium>]
#
# The archive is a deliberate mirror of the SD card payload: only
#   .minime/{kernel,initramfs,system,dtb,devices/*.dtb,ui.env,manifest.json}  (OS + contract + build identity)
#   .system/...                                              (UI binaries)
# are packaged. User data (Bios/, Roms/, Saves/, Emus/, Tools/, .userdata/) is
# never included, so extracting the archive onto /mnt/sdcard cannot clobber it.

set -eu

usage() {
	echo "Usage: ${0##*/} --target <alpine|buildroot> --board <h700|rk3326|rk3566> --input-dir <dir> --output-dir <dir> [--ui <minui|allium>]" >&2
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

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD_DIR="${MINIME_ROOT}/minime/boards/${BOARD}"

mkdir -p "${OUTPUT_DIR}"

WORK_TMP="$(mktemp -d)"
cleanup() {
	rm -rf "${WORK_TMP}"
}
trap cleanup EXIT

STAGE_DIR="${WORK_TMP}/update"
mkdir -p "${STAGE_DIR}/.minime/devices"

[ -f "${INPUT_DIR}/Image" ] || {
	echo "ERROR: Image missing" >&2
	exit 1
}
[ -f "${INPUT_DIR}/initramfs.img" ] || {
	echo "ERROR: initramfs.img missing" >&2
	exit 1
}
[ -f "${INPUT_DIR}/system.erofs" ] || {
	echo "ERROR: system.erofs missing" >&2
	exit 1
}

# --- OS payload (.minime/) -------------------------------------------------
cp -f "${INPUT_DIR}/Image" "${STAGE_DIR}/.minime/kernel"
cp -f "${INPUT_DIR}/initramfs.img" "${STAGE_DIR}/.minime/initramfs"
cp -f "${INPUT_DIR}/system.erofs" "${STAGE_DIR}/.minime/system"

if [ -d "${INPUT_DIR}/devices" ]; then
	cp -f "${INPUT_DIR}/devices/"*.dtb "${STAGE_DIR}/.minime/devices/" 2>/dev/null || true
fi
cp -f "${INPUT_DIR}"/*.dtb "${STAGE_DIR}/.minime/devices/" 2>/dev/null || true

# Stage the default DTB the bootloader actually loads (boot.cmd fatloads
# .minime/dtb). Without this, DTS-affecting changes never reach the device
# over OTA, only via a full image reflash. Mirrors mkimage.sh.
DEFAULT_DEVICE="${DEFAULT_DEVICE:-}"
if [ -z "${DEFAULT_DEVICE}" ] && [ -f "${BOARD_DIR}/boot.env" ]; then
	DEFAULT_DEVICE="$(grep '^DEFAULT_DEVICE=' "${BOARD_DIR}/boot.env" | head -1 | cut -d= -f2- | tr -d '"' || true)"
fi

if [ -n "${DEFAULT_DEVICE}" ] && [ -f "${STAGE_DIR}/.minime/devices/${DEFAULT_DEVICE}" ]; then
	cp -f "${STAGE_DIR}/.minime/devices/${DEFAULT_DEVICE}" "${STAGE_DIR}/.minime/dtb"
else
	first_dtb="$(ls "${STAGE_DIR}/.minime/devices/"*.dtb 2>/dev/null | head -1 || true)"
	if [ -n "${first_dtb}" ]; then
		cp -f "${first_dtb}" "${STAGE_DIR}/.minime/dtb"
	fi
fi

# --- UI payload (.system/ + .minime/ui.env) --------------------------------
if [ -n "${UI}" ]; then
	# genassets.sh stages the UI into ${INPUT_DIR}/ui before image assembly.
	UI_STAGE="${INPUT_DIR}/ui"
	if [ -d "${UI_STAGE}/.system" ]; then
		cp -rf "${UI_STAGE}/.system" "${STAGE_DIR}/.system"
	else
		echo "ERROR: UI payload (.system) not found in ${UI_STAGE}" >&2
		exit 1
	fi
	if [ -f "${UI_STAGE}/.minime/ui.env" ]; then
		cp -f "${UI_STAGE}/.minime/ui.env" "${STAGE_DIR}/.minime/ui.env"
	fi
fi

# Build identity: record the commits this archive was built from so the
# installed image can be checked against the latest release. Prefer the
# caller-supplied values (set by CI/host from the checkout) over computing
# them here, since the packaging container may not carry a usable .git.
MINIME_COMMIT="${MINIME_COMMIT:-$(git -C "${MINIME_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
UI_COMMIT="${UI_COMMIT:-$(git -C "${MINIME_ROOT}/minime/ui/${UI}" rev-parse --short HEAD 2>/dev/null || echo unknown)}"

cat <<EOF >"${STAGE_DIR}/.minime/manifest.json"
{
  "target": "${TARGET}",
  "board": "${BOARD}",
  "ui": "${UI}",
  "minime_commit": "${MINIME_COMMIT}",
  "ui_commit": "${UI_COMMIT}",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF

if [ -n "${UI}" ]; then
	UPDATE_PKG="${OUTPUT_DIR}/minime-${TARGET}-${BOARD}-${UI}.tar.zst"
else
	UPDATE_PKG="${OUTPUT_DIR}/minime-${TARGET}-${BOARD}.tar.zst"
fi
(cd "${STAGE_DIR}" && tar -cf - . | zstd -q -9 >"${UPDATE_PKG}")

echo "Update package created: ${UPDATE_PKG}"
