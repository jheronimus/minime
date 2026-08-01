#!/bin/sh
# shellcheck shell=sh
# Minime Payload Fetcher
# Downloads and stages OS-agnostic FAT32 payloads (UI and preloaded-roms)
# directly into the image staging directory, bypassing EROFS OS builds.

set -eu

usage() {
	echo "Usage: ${0##*/} <minui|allium|none> <dest_dir> [alpine|buildroot|musl|glibc]" >&2
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
UI_ART_DIR="${MINIME_ROOT}/minime/ui/out"

if [ "$UI" = "minui" ]; then
	local_zip="${UI_ART_DIR}/minui-${LIBC}-aarch64.zip"
	local_tar="${UI_ART_DIR}/minui-${LIBC}-aarch64.tar.xz"

	if [ -f "${local_zip}" ]; then
		echo "Using local UI artifact: ${local_zip}" >&2
		unzip -q -o "${local_zip}" -d "${WORK_TMP}/minui"
	elif [ -f "${local_tar}" ]; then
		echo "Using local UI artifact: ${local_tar}" >&2
		mkdir -p "${WORK_TMP}/minui"
		tar -xf "${local_tar}" -C "${WORK_TMP}/minui"
	else
		echo "Local MinUI artifact not found in ${UI_ART_DIR}/, attempting download from latest-ui release..." >&2
		dl_tar="${WORK_TMP}/minui-${LIBC}-aarch64.tar.xz"
		if curl -fL --retry 3 -o "${dl_tar}" "https://github.com/jheronimus/minime/releases/download/latest-ui/minui-${LIBC}-aarch64.tar.xz"; then
			mkdir -p "${WORK_TMP}/minui"
			tar -xf "${dl_tar}" -C "${WORK_TMP}/minui"
		else
			echo "ERROR: MinUI artifact not found locally and download failed." >&2
			echo "Run the minui.yml workflow or 'just build-minui' to generate it." >&2
			exit 1
		fi
	fi

	[ -f "${WORK_TMP}/minui/MinUI.zip" ] && unzip -q -o "${WORK_TMP}/minui/MinUI.zip" -d "${WORK_TMP}/minui"

	[ -d "${WORK_TMP}/minui/.system" ] && cp -a "${WORK_TMP}/minui/.system" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/minui/.minime" ] && cp -a "${WORK_TMP}/minui/.minime" "${DEST_DIR}/"

	# Strip .elf extensions (MinUI convention; Minime expects bare names)
	for f in "${DEST_DIR}/.system/minime/bin/"*.elf; do
		[ -f "$f" ] && mv -f "$f" "${f%.elf}"
	done

	[ -d "${WORK_TMP}/minui/Emus" ] && cp -a "${WORK_TMP}/minui/Emus" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/minui/Tools" ] && cp -a "${WORK_TMP}/minui/Tools" "${DEST_DIR}/"

elif [ "$UI" = "allium" ]; then
	local_zip="${UI_ART_DIR}/allium-${LIBC}-aarch64.zip"
	local_tar="${UI_ART_DIR}/allium-${LIBC}-aarch64.tar.xz"

	if [ -f "${local_zip}" ]; then
		echo "Using local UI artifact: ${local_zip}" >&2
		unzip -q -o "${local_zip}" -d "${WORK_TMP}/allium"
	elif [ -f "${local_tar}" ]; then
		echo "Using local UI artifact: ${local_tar}" >&2
		mkdir -p "${WORK_TMP}/allium"
		tar -xf "${local_tar}" -C "${WORK_TMP}/allium"
	else
		echo "Local Allium artifact not found in ${UI_ART_DIR}/, attempting download from latest-ui release..." >&2
		dl_tar="${WORK_TMP}/allium-${LIBC}-aarch64.tar.xz"
		if curl -fL --retry 3 -o "${dl_tar}" "https://github.com/jheronimus/minime/releases/download/latest-ui/allium-${LIBC}-aarch64.tar.xz"; then
			mkdir -p "${WORK_TMP}/allium"
			tar -xf "${dl_tar}" -C "${WORK_TMP}/allium"
		else
			echo "ERROR: Allium artifact not found locally and download failed." >&2
			echo "Run the allium.yml workflow or 'just build-allium' to generate it." >&2
			exit 1
		fi
	fi

	[ -d "${WORK_TMP}/allium/.ui" ] && cp -a "${WORK_TMP}/allium/.ui" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/allium/.minime" ] && cp -a "${WORK_TMP}/allium/.minime" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/allium/apps" ] && cp -a "${WORK_TMP}/allium/apps" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/allium/.tmp_update" ] && cp -a "${WORK_TMP}/allium/.tmp_update" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/allium/RetroArch" ] && cp -a "${WORK_TMP}/allium/RetroArch" "${DEST_DIR}/"
fi

# 2. Stage Preloaded ROMs
if [ -f "${MINIME_ROOT}/roms/install.sh" ]; then
	echo "Installing preloaded ROMs..."
	sh "${MINIME_ROOT}/roms/install.sh" "${DEST_DIR}"
fi

echo "Payload staging complete."
