#!/usr/bin/env sh
set -eu

DEST_DIR="$1" # Target staging directory (e.g. /alpine-output/boot/ui or $(BINARIES_DIR)/ui)

ROMS_SRC="/workspace/roms"
if [ ! -d "${ROMS_SRC}" ]; then
	# Fallback if run from a different context
	ROMS_SRC="$(cd "$(dirname "$0")" && pwd)"
fi

log() {
	echo "  [roms] $*"
}

log "Installing ROMs to ${DEST_DIR}..."

# Ensure Roms root directory exists
mkdir -p "${DEST_DIR}/Roms"

# System mappings come from the shared roms/mappings file (single source of
# truth). Both UIs use the same MinUI-canonical folder names, so there is no
# per-UI naming here.
# Format: short_name|roms_dir
mappings_file="${ROMS_SRC}/mappings"
if [ ! -f "${mappings_file}" ]; then
	log "Error: mappings file not found: ${mappings_file}"
	exit 1
fi

while IFS='|' read -r src_name roms_dir || [ -n "${src_name}" ]; do
	case "${src_name}" in "" | \#*) continue ;; esac
	[ -n "${roms_dir}" ] || continue

	src_dir="${ROMS_SRC}/${src_name}"
	[ -d "${src_dir}" ] || continue

	target_dir="${DEST_DIR}/Roms/${roms_dir}"
	log "Copying ${src_name} -> ${target_dir}..."
	mkdir -p "${target_dir}"
	cp -rp "${src_dir}/." "${target_dir}/"
done <"${mappings_file}"

log "ROM installation complete."
