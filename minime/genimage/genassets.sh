#!/bin/sh
# shellcheck shell=sh
# Minime Payload Fetcher
# Downloads and stages OS-agnostic FAT32 payloads (UI and preloaded-roms)
# directly into the image staging directory, bypassing EROFS OS builds.

set -eu

usage() {
	echo "Usage: ${0##*/} <minui|allium|none> <dest_dir>" >&2
	exit 1
}

UI="${1:-}"
DEST_DIR="${2:-}"

if [ -z "$UI" ] || [ -z "$DEST_DIR" ]; then
	usage
fi

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
WORK_TMP="$(mktemp -d)"

cleanup() {
	rm -rf "${WORK_TMP}"
}
trap cleanup EXIT

mkdir -p "${DEST_DIR}"

fetch_and_verify() {
	url="$1"
	expected_sha512="$2"
	filename=$(basename "$url")
	filepath="${WORK_TMP}/${filename}"

	echo "Downloading ${filename}..." >&2
	curl -sL --retry 3 "${url}" -o "${filepath}"

	actual_sha512=$(shasum -a 512 "${filepath}" | cut -d' ' -f1)
	if [ "$actual_sha512" != "$expected_sha512" ]; then
		echo "ERROR: SHA512 mismatch for ${filename}" >&2
		echo "Expected: ${expected_sha512}" >&2
		echo "Actual:   ${actual_sha512}" >&2
		exit 1
	fi
	echo "${filepath}"
}

echo "=== Staging Payloads to ${DEST_DIR} ==="

# 1. Stage UI
if [ "$UI" = "minui" ]; then
	MINUI_VER="20260722"
	MINUI_DOT="0"
	
	base_zip=$(fetch_and_verify "https://github.com/jheronimus/MinUI/releases/download/v${MINUI_VER}/MinUI-${MINUI_VER}-${MINUI_DOT}-base.zip" "23abbd083038d317f7bcc62aee32632c863ec43728b9f80d167b06c103f80581cb6733992a066e46e334e3b5b24d6d80ddb9b4ce28c526006f836ffb11cceca2" | tail -n 1)
	extras_zip=$(fetch_and_verify "https://github.com/jheronimus/MinUI/releases/download/v${MINUI_VER}/MinUI-${MINUI_VER}-${MINUI_DOT}-extras.zip" "3bcbfa82816a5ff993bed766c6423b1e36bb108764aa5ae45ad479ff540ce5d9ad9999b12a2039925de9f64f7789aa88c5fae4cddf86a67315b79cf7045037ca" | tail -n 1)

	unzip -q -o "${base_zip}" -d "${WORK_TMP}/minui"
	unzip -q -o "${WORK_TMP}/minui/MinUI.zip" -d "${WORK_TMP}/minui"
	unzip -q -o "${extras_zip}" -d "${WORK_TMP}/minui"

	[ -d "${WORK_TMP}/minui/.system" ] && cp -a "${WORK_TMP}/minui/.system" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/minui/.minime" ] && cp -a "${WORK_TMP}/minui/.minime" "${DEST_DIR}/"
	
	# Strip .elf extensions (MinUI convention; Minime expects bare names)
	for f in "${DEST_DIR}/.system/minime/bin/"*.elf; do
		[ -f "$f" ] && mv -f "$f" "${f%.elf}"
	done

	[ -d "${WORK_TMP}/minui/Emus" ] && cp -a "${WORK_TMP}/minui/Emus" "${DEST_DIR}/"
	[ -d "${WORK_TMP}/minui/Tools" ] && cp -a "${WORK_TMP}/minui/Tools" "${DEST_DIR}/"

elif [ "$UI" = "allium" ]; then
	ALLIUM_VER="20260720"
	
	allium_zip=$(fetch_and_verify "https://github.com/jheronimus/Allium/releases/download/v${ALLIUM_VER}/allium-minime-aarch64.zip" "579a51cad525fc04d024c1474532267a4a28b15f232b3305d1b495007ff6bd8558eb2ba4e1f4e154d1a511ca0ff1da7d0eae1660b6dc6409dfa647300147f79a" | tail -n 1)
	unzip -q -o "${allium_zip}" -d "${WORK_TMP}/allium"

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
