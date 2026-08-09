#!/usr/bin/env sh
set -eu

DEST_DIR="$1" # Target staging directory (e.g. /alpine-output/boot/ui or $(BINARIES_DIR)/ui)
UI_TYPE="${2:-auto}"

ROMS_SRC="/workspace/roms"
if [ ! -d "${ROMS_SRC}" ]; then
	# Fallback if run from a different context
	ROMS_SRC="$(cd "$(dirname "$0")" && pwd)"
fi

log() {
	echo "  [roms] $*"
}

# Auto-detect UI if not explicitly specified
if [ "${UI_TYPE}" = "auto" ] || [ -z "${UI_TYPE}" ]; then
	if [ -d "${DEST_DIR}/.system" ]; then
		UI_TYPE="minui"
	elif [ -d "${DEST_DIR}/.ui" ]; then
		UI_TYPE="allium"
	else
		log "Warning: UI type could not be auto-detected. Defaulting to allium."
		UI_TYPE="allium"
	fi
fi

log "Installing ROMs to ${DEST_DIR} for UI: ${UI_TYPE}..."

# Ensure Roms root directory exists
mkdir -p "${DEST_DIR}/Roms"

# System mappings come from the shared roms/mappings file (single source of
# truth, also consumed by the on-device update.sh for UI-switch renames).
# Format: short_name|minui_name|allium_name
mappings_file="${ROMS_SRC}/mappings"
if [ ! -f "${mappings_file}" ]; then
	log "Error: mappings file not found: ${mappings_file}"
	exit 1
fi

while IFS='|' read -r src_name minui_name allium_name || [ -n "${src_name}" ]; do
	case "${src_name}" in "" | \#*) continue ;; esac
	[ -n "${minui_name}" ] || continue
	[ -n "${allium_name}" ] || continue

	src_dir="${ROMS_SRC}/${src_name}"
	[ -d "${src_dir}" ] || continue

	# Determine the target directory name
	if [ "${UI_TYPE}" = "minui" ]; then
		target_dir="${DEST_DIR}/Roms/${minui_name}"
	else
		target_dir="${DEST_DIR}/Roms/${allium_name}"
	fi

	log "Copying ${src_name} -> ${target_dir}..."
	mkdir -p "${target_dir}"
	cp -rp "${src_dir}/." "${target_dir}/"
done <"${mappings_file}"

log "ROM installation complete."
