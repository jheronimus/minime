#!/bin/sh
# shellcheck shell=sh
# Minime Payload Fetcher
# Downloads and stages OS-agnostic FAT32 payloads (UI and preloaded-roms)
# directly into the image staging directory, bypassing EROFS OS builds.

set -eu

usage() {
	echo "Usage: ${0##*/} <minui|allium|muos|none> <dest_dir> [alpine|buildroot|musl|glibc]" >&2
	exit 1
}

UI="${1:-}"
DEST_DIR="${2:-}"
TARGET_RAW="${3:-alpine}"

if [ -z "$UI" ] || [ -z "$DEST_DIR" ]; then
	usage
fi

case "${TARGET_RAW}" in
	alpine|musl) LIBC="musl" ;;
	buildroot|glibc) LIBC="glibc" ;;
	*) LIBC="musl" ;;
esac

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
WORK_TMP="$(mktemp -d)"

cleanup() {
	rm -rf "${WORK_TMP}"
}
trap cleanup EXIT

mkdir -p "${DEST_DIR}"

echo "=== Staging Payloads to ${DEST_DIR} (${LIBC}) ==="

# 1. Stage UI
UI_ART_DIR="${MINIME_ROOT}/packages/ui/out"

if [ "$UI" = "minui" ]; then
	local_zip="${UI_ART_DIR}/minui-${LIBC}-aarch64.zip"
	local_tar="${UI_ART_DIR}/minui-${LIBC}-aarch64.tar.zst"

	if [ -f "${local_zip}" ]; then
		echo "Using local UI artifact: ${local_zip}" >&2
		unzip -q -o "${local_zip}" -d "${DEST_DIR}"
	elif [ -f "${local_tar}" ]; then
		echo "Using local UI artifact: ${local_tar}" >&2
		unzstd -q -c "${local_tar}" | tar -xf - -C "${DEST_DIR}"
	else
		echo "ERROR: Local MinUI artifact not found in ${UI_ART_DIR}/." >&2
		echo "Run the build-ui job or 'just build-minui' to generate it." >&2
		exit 1
	fi

	if [ -f "${DEST_DIR}/MinUI.zip" ]; then
		unzip -q -o "${DEST_DIR}/MinUI.zip" -d "${DEST_DIR}"
		rm -f "${DEST_DIR}/MinUI.zip"
	fi
	if [ -f "${DEST_DIR}/MinUI-extras.zip" ]; then
		unzip -q -o "${DEST_DIR}/MinUI-extras.zip" -d "${DEST_DIR}"
		rm -f "${DEST_DIR}/MinUI-extras.zip"
	fi

elif [ "$UI" = "allium" ]; then
	local_zip="${UI_ART_DIR}/allium-${LIBC}-aarch64.zip"
	local_tar="${UI_ART_DIR}/allium-${LIBC}-aarch64.tar.zst"

	if [ -f "${local_zip}" ]; then
		echo "Using local UI artifact: ${local_zip}" >&2
		unzip -q -o "${local_zip}" -d "${DEST_DIR}"
	elif [ -f "${local_tar}" ]; then
		echo "Using local UI artifact: ${local_tar}" >&2
		unzstd -q -c "${local_tar}" | tar -xf - -C "${DEST_DIR}"
	else
		echo "ERROR: Local Allium artifact not found in ${UI_ART_DIR}/." >&2
		echo "Run the build-ui job or 'just build-allium' to generate it." >&2
		exit 1
	fi

elif [ "$UI" = "muos" ]; then
	local_zip="${UI_ART_DIR}/muos-${LIBC}-aarch64.zip"
	local_tar="${UI_ART_DIR}/muos-${LIBC}-aarch64.tar.zst"

	if [ -f "${local_zip}" ]; then
		echo "Using local UI artifact: ${local_zip}" >&2
		unzip -q -o "${local_zip}" -d "${DEST_DIR}"
	elif [ -f "${local_tar}" ]; then
		echo "Using local UI artifact: ${local_tar}" >&2
		unzstd -q -c "${local_tar}" | tar -xf - -C "${DEST_DIR}"
	else
		echo "ERROR: Local muOS artifact not found in ${UI_ART_DIR}/." >&2
		echo "Run the build-ui job or 'just build-muos' to generate it." >&2
		exit 1
	fi
fi

# 2. Stage Preloaded ROMs
if [ -f "${MINIME_ROOT}/roms/install.sh" ]; then
	echo "Installing preloaded ROMs..."
	sh "${MINIME_ROOT}/roms/install.sh" "${DEST_DIR}"
fi

echo "Payload staging complete."
