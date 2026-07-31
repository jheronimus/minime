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

fetch_and_verify() {
	url="$1"
	expected_sha512="${2:-}"
	filename=$(basename "$url")
	filepath="${WORK_TMP}/${filename}"

	echo "Downloading ${filename}..." >&2
	curl -sL --retry 3 "${url}" -o "${filepath}"

	if [ -n "${expected_sha512}" ]; then
		actual_sha512=$(sha512sum "${filepath}" | cut -d' ' -f1)
		if [ "$actual_sha512" != "$expected_sha512" ]; then
			echo "ERROR: SHA512 mismatch for ${filename}" >&2
			echo "Expected: ${expected_sha512}" >&2
			echo "Actual:   ${actual_sha512}" >&2
			exit 1
		fi
	fi
	echo "${filepath}"
}

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
		MINUI_VER="20260722"
		minui_zip=$(fetch_and_verify "https://github.com/jheronimus/MinUI/releases/download/v${MINUI_VER}/minui-${MINUI_VER}-${LIBC}-aarch64.zip" | tail -n 1)
		unzip -q -o "${minui_zip}" -d "${WORK_TMP}/minui"
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
		ALLIUM_VER="20260720"
		allium_zip=$(fetch_and_verify "https://github.com/jheronimus/Allium/releases/download/v${ALLIUM_VER}/allium-${ALLIUM_VER}-${LIBC}-aarch64.zip" | tail -n 1)
		unzip -q -o "${allium_zip}" -d "${WORK_TMP}/allium"
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
