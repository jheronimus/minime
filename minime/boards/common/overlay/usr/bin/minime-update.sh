#!/bin/sh
# shellcheck shell=sh
# minime-update: self-update Minime from the GitHub "testing" release.
#
# Usage: minime-update <minui|allium>
#
# Detects board (h700/rk3326/rk3566) and target (alpine/buildroot) on-device,
# downloads the matching OTA archive directly with curl, compares it against
# the installed manifest, and installs it (clean-replace .system, overlay
# .minime), then removes the archive and reboots.
#
# The archive is staged in /mnt/sdcard/.minime/update/ (NOT /tmp — /tmp is a
# tiny tmpfs). The staging dir is removed before rebooting.

set -eu

# --- Configuration ---------------------------------------------------------

REPO="jheronimus/minime"
RELEASE="testing"
SDCARD="/mnt/sdcard"
STAGE_DIR="${SDCARD}/.minime/update"
INSTALLED_MANIFEST="${SDCARD}/.minime/manifest.json"
TRAITS_FILE="${SDCARD}/.minime/traits"

# --- Helpers --------------------------------------------------------------

usage() {
	echo "Usage: ${0##*/} <minui|allium>" >&2
	exit 1
}

log() {
	echo "[minime-update] $*"
}

die() {
	log "ERROR: $*" >&2
	exit 1
}

# Detect the board (h700/rk3326/rk3566) from the kernel compatible string,
# falling back to the staged dtb filename.
detect_board() {
	compat="$(tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null || true)"
	case "${compat}" in
	*"sun50i-h700"*) echo "h700" ;;
	*"rk3326"*) echo "rk3326" ;;
	*"rk3566"*) echo "rk3566" ;;
	*)
		# Fallback: /mnt/sdcard/.minime/dtb, e.g. sun50i-h700-*.dtb
		dtb="$(basename "${SDCARD}/.minime/dtb" 2>/dev/null || true)"
		case "${dtb}" in
		"sun50i-h700-"*) echo "h700" ;;
		"rk3326-"*) echo "rk3326" ;;
		"rk3566-"*) echo "rk3566" ;;
		*) die "cannot detect board (compatible='${compat}' dtb='${dtb}')" ;;
		esac
		;;
	esac
}

# Detect the target (alpine/buildroot) from /etc/os-release.
detect_target() {
	if grep -q '^ID=alpine' /etc/os-release 2>/dev/null; then
		echo "alpine"
	elif grep -qi '^ID=buildroot' /etc/os-release 2>/dev/null; then
		echo "buildroot"
	else
		# Fallback: gpu_driver trait (panfrost=alpine, mali_kbase=buildroot)
		if grep -q '^gpu_driver=mali_kbase' "${TRAITS_FILE}" 2>/dev/null; then
			echo "buildroot"
		else
			echo "alpine"
		fi
	fi
}

# --- Main -----------------------------------------------------------------

UI="${1:-}"
[ -n "${UI}" ] || usage
case "${UI}" in
minui | allium) ;;
*) die "unsupported UI '${UI}' (expected minui or allium)" ;;
esac

BOARD="$(detect_board)"
TARGET="$(detect_target)"
log "board=${BOARD} target=${TARGET} ui=${UI}"

[ -x /usr/bin/curl ] || die "curl is not available on this image"
[ -d "${SDCARD}" ] || die "no SD card at ${SDCARD}"

ARCHIVE="${STAGE_DIR}/minime-${TARGET}-${BOARD}-${UI}.tar.xz"
URL="https://github.com/${REPO}/releases/download/${RELEASE}/minime-${TARGET}-${BOARD}-${UI}.tar.xz"

log "Checking ${URL}"
mkdir -p "${STAGE_DIR}"

# Download. curl with -L follows the release redirect; --fail surfaces HTTP errors.
if ! curl -L --fail --show-error -o "${ARCHIVE}" "${URL}"; then
	rm -f "${ARCHIVE}"
	die "download failed for ${URL}"
fi

SIZE="$(wc -c <"${ARCHIVE}" 2>/dev/null || echo 0)"
log "downloaded ${SIZE} bytes"

# Compare the archive's manifest against the installed one.
REMOTE_MANIFEST="$(tar -xJOf "${ARCHIVE}" ./.minime/manifest.json 2>/dev/null || true)"
if [ -n "${REMOTE_MANIFEST}" ] && [ -f "${INSTALLED_MANIFEST}" ]; then
	rem_min="$(echo "${REMOTE_MANIFEST}" | sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' | head -n1)"
	rem_ui="$(echo "${REMOTE_MANIFEST}" | sed -n 's/.*"ui_commit": *"\([^"]*\)".*/\1/p' | head -n1)"
	loc_min="$(sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' "${INSTALLED_MANIFEST}" | head -n1)"
	loc_ui="$(sed -n 's/.*"ui_commit": *"\([^"]*\)".*/\1/p' "${INSTALLED_MANIFEST}" | head -n1)"

	if [ "${rem_min}" = "${loc_min}" ] && [ "${rem_ui}" = "${loc_ui}" ] &&
		[ -n "${rem_min}" ] && [ "${rem_min}" != "unknown" ]; then
		log "already up to date (${rem_min}/${rem_ui})"
		rm -f "${ARCHIVE}"
		rmdir "${STAGE_DIR}" 2>/dev/null || true
		exit 0
	fi
fi

log "installing ${SIZE} bytes (${rem_min:-?}/${rem_ui:-?})..."

# Stop the UI so it is not running from files we are about to replace.
/etc/init.d/ui stop >/dev/null 2>&1 || true
killall -9 minui.elf minarch.elf keymon.elf 2>/dev/null || true
sleep 1

# Apply: .system clean-replaced (UI payload), .minime overlaid (state kept).
rm -rf "${SDCARD}/.system"
tar -xJf "${ARCHIVE}" -C "${SDCARD}"

# Verify the payload landed before removing the archive.
[ -f "${SDCARD}/.system/version.txt" ] ||
	die "install incomplete: .system/version.txt missing; leaving archive at ${ARCHIVE}"

# Clean up the archive and stage dir before rebooting.
rm -f "${ARCHIVE}"
rmdir "${STAGE_DIR}" 2>/dev/null || true

log "update installed; rebooting"
sync
reboot
exit 0
