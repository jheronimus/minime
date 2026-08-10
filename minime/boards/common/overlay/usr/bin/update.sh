#!/bin/sh
# shellcheck shell=sh
# update: self-update Minime from the GitHub "testing" release.
#
# Usage: update <minui|allium>
#
# Detects board (h700/rk3326/rk3566) and target (alpine/buildroot) on-device,
# downloads the matching OTA archive directly with curl, compares it against
# the installed manifest, and installs it (clean-replaces the active UI
# payload — .system for MinUI, .ui/.allium/RetroArch/apps for Allium —
# and overlays .minime).  When the requested UI differs from the installed
# UI, Roms/ subfolders are renamed to the new UI's naming convention using
# the shared /usr/share/minime/rom-mappings table (the same source as the
# preloaded-ROM installer).  User data (ROMs content, Saves/, Bios/,
# .userdata/) is never touched beyond those Roms/ folder renames.
#
# The script detaches from the invoking shell by default (telnet-safe) and
# logs to the SD card, so it survives the session dropping.  It reboots the
# device when the update has been applied.

set -eu

# --- Configuration ---------------------------------------------------------

REPO="jheronimus/minime"
RELEASE="testing"
SDCARD="/mnt/sdcard"
UPDATE_DIR="${SDCARD}/.minime/update"
LOG_FILE="${UPDATE_DIR}/update.log"
PID_FILE="${UPDATE_DIR}/update.pid"
INSTALLED_MANIFEST="${SDCARD}/.minime/manifest.json"
UI_ENV_FILE="${SDCARD}/.minime/ui.env"
TRAITS_FILE="${SDCARD}/.minime/traits"
ROM_MAPPINGS="/usr/share/minime/rom-mappings"

# --- Helpers --------------------------------------------------------------

usage() {
	echo "Usage: ${0##*/} <minui|allium>" >&2
	exit 1
}

log() {
	echo "[update] $*"
}

die() {
	log "ERROR: $*" >&2
	exit 1
}

# Detach from the invoking shell (telnet-safe): re-run ourselves under setsid
# with output redirected to the SD-card log, then return immediately.
detach() {
	mkdir -p "${UPDATE_DIR}"
	if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
		echo "[update] ERROR: already running (pid $(cat "${PID_FILE}" 2>/dev/null))" >&2
		exit 1
	fi
	echo "[update] starting in background; log: ${LOG_FILE}"
	UPDATE_DETACHED=1 setsid /bin/sh "$0" "$@" </dev/null >>"${LOG_FILE}" 2>&1 &
	echo $! >"${PID_FILE}"
	exit 0
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

# Normalized (lowercase) UI name of the currently installed payload.
installed_ui() {
	[ -f "${UI_ENV_FILE}" ] || return 0
	grep '^UI_NAME=' "${UI_ENV_FILE}" 2>/dev/null | head -n1 |
		cut -d= -f2- | tr -d '"' | tr 'A-Z' 'a-z'
}

# Rename Roms/ subfolders from the old UI's naming to the new UI's naming.
# Only the shared preloaded systems (rom-mappings) are handled; a rename is
# skipped when the target folder already exists (never nest or clobber).
rename_roms() {
	from="$1"
	to="$2"
	[ "${from}" = "${to}" ] && return 0
	[ -n "${from}" ] && [ -n "${to}" ] || {
		log "installed UI unknown; skipping Roms rename"
		return 0
	}
	[ -f "${ROM_MAPPINGS}" ] || {
		log "missing ${ROM_MAPPINGS}; skipping Roms rename"
		return 0
	}
	renamed=0
	while IFS='|' read -r short minui_name allium_name || [ -n "${short}" ]; do
		case "${short}" in "" | \#*) continue ;; esac
		[ -n "${minui_name}" ] || continue
		[ -n "${allium_name}" ] || continue
		if [ "${from}" = "minui" ]; then
			old="${minui_name}"
			new="${allium_name}"
		else
			old="${allium_name}"
			new="${minui_name}"
		fi
		[ "${old}" = "${new}" ] && continue
		if [ -d "${SDCARD}/Roms/${old}" ] && [ ! -e "${SDCARD}/Roms/${new}" ]; then
			mv "${SDCARD}/Roms/${old}" "${SDCARD}/Roms/${new}"
			log "Roms: '${old}' -> '${new}'"
			renamed=$((renamed + 1))
		fi
	done <"${ROM_MAPPINGS}"
	log "Roms rename complete (${renamed} folder(s) renamed)"
}

# --- Main -----------------------------------------------------------------

UI="${1:-}"
[ -n "${UI}" ] || usage
UI="$(echo "${UI}" | tr 'A-Z' 'a-z')"
case "${UI}" in
minui | allium) ;;
*) die "unsupported UI '${UI}' (expected minui or allium)" ;;
esac

if [ "${UPDATE_DETACHED:-0}" != "1" ]; then
	detach "$UI"
fi

echo $$ >"${PID_FILE}"
trap 'rm -f "${PID_FILE}"' EXIT

BOARD="$(detect_board)"
TARGET="$(detect_target)"
FROM_UI="$(installed_ui)"
log "board=${BOARD} target=${TARGET} ui=${UI} installed_ui=${FROM_UI:-unknown}"

[ -x /usr/bin/curl ] || die "curl is not available on this image"
[ -d "${SDCARD}" ] || die "no SD card at ${SDCARD}"

ARCHIVE="${UPDATE_DIR}/minime-${TARGET}-${BOARD}-${UI}.tar.zst"
URL="https://github.com/${REPO}/releases/download/${RELEASE}/minime-${TARGET}-${BOARD}-${UI}.tar.zst"

log "Checking ${URL}"
mkdir -p "${UPDATE_DIR}"

# Download. curl with -L follows the release redirect; --fail surfaces HTTP errors.
if ! curl -L --fail --show-error -o "${ARCHIVE}" "${URL}"; then
	rm -f "${ARCHIVE}"
	die "download failed for ${URL}"
fi

SIZE="$(wc -c <"${ARCHIVE}" 2>/dev/null || echo 0)"
log "downloaded ${SIZE} bytes"

# Compare the archive's manifest against the installed one.
REMOTE_MANIFEST="$(unzstd -c "${ARCHIVE}" 2>/dev/null | tar -xOf - ./.minime/manifest.json 2>/dev/null || true)"
if [ -n "${REMOTE_MANIFEST}" ] && [ -f "${INSTALLED_MANIFEST}" ]; then
	rem_min="$(echo "${REMOTE_MANIFEST}" | sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' | head -n1)"
	rem_ui="$(echo "${REMOTE_MANIFEST}" | sed -n 's/.*"ui_commit": *"\([^"]*\)".*/\1/p' | head -n1)"
	loc_min="$(sed -n 's/.*"minime_commit": *"\([^"]*\)".*/\1/p' "${INSTALLED_MANIFEST}" | head -n1)"
	loc_ui="$(sed -n 's/.*"ui_commit": *"\([^"]*\)".*/\1/p' "${INSTALLED_MANIFEST}" | head -n1)"

	if [ "${rem_min}" = "${loc_min}" ] && [ "${rem_ui}" = "${loc_ui}" ] &&
		[ -n "${rem_min}" ] && [ "${rem_min}" != "unknown" ]; then
		log "already up to date (${rem_min}/${rem_ui})"
		rm -f "${ARCHIVE}"
		rmdir "${UPDATE_DIR}" 2>/dev/null || true
		exit 0
	fi
fi

log "installing ${SIZE} bytes (${rem_min:-?}/${rem_ui:-?})..."

# Stop the UI so it is not running from files we are about to replace.
/etc/init.d/ui stop >/dev/null 2>&1 || true
killall -9 minui.elf minarch.elf keymon.elf 2>/dev/null || true
sleep 1

# Apply: UI payload clean-replaced, .minime overlaid (state kept).
# MinUI lives under .system/; Allium under .ui/ + .allium/ + RetroArch/ +
# apps/ + Roms/ + Saves/ + BIOS/.  Remove the old UI's top-level dirs so a
# UI switch does not leave stale binaries, then extract the whole archive.
case "${FROM_UI:-}" in
minui) rm -rf "${SDCARD}/.system" ;;
allium)
	rm -rf "${SDCARD}/.ui" "${SDCARD}/.allium" \
		"${SDCARD}/RetroArch" "${SDCARD}/apps"
	;;
esac
unzstd -c "${ARCHIVE}" | tar -xf - -C "${SDCARD}"

# Verify the payload landed before removing the archive.
case "${UI}" in
minui)
	[ -f "${SDCARD}/.system/version.txt" ] ||
		die "install incomplete: .system/version.txt missing; leaving archive at ${ARCHIVE}"
	;;
allium)
	[ -x "${SDCARD}/.ui/bin/alliumd" ] ||
		die "install incomplete: .ui/bin/alliumd missing; leaving archive at ${ARCHIVE}"
	;;
esac

# Rename Roms/ subfolders when the UI changed (uses the pre-switch installed UI).
rename_roms "${FROM_UI}" "${UI}"

# Clean up the archive before rebooting.
rm -f "${ARCHIVE}"

# Mark this as a software-initiated reboot so the charger-triggered-boot
# guard (init.d/charger) does not power the device back off when the charger
# is connected (ADR 0020).  Cleared by the charger service on next boot.
touch "${SDCARD}/.minime/config/.software_reboot"

log "update installed; rebooting"
sync
reboot
exit 0
