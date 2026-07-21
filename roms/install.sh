#!/usr/bin/env sh
set -eu

DEST_DIR="$1"  # Target staging directory (e.g. /alpine-output/boot/ui or $(BINARIES_DIR)/ui)
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

# System mappings
# Format: short_name|minui_name
mappings="
gb|Game Boy (GB)
gba|Game Boy Advance (GBA)
nes|Nintendo Entertainment System (FC)
snes|Super Nintendo (SFC)
md|Sega Genesis (MD)
gg|Game Gear (GG)
sms|Master System (SMS)
psx|Sony PlayStation (PS)
pce|PC Engine (PCE)
lynx|Atari Lynx (LYNX)
ngp|Neo Geo Pocket (NGP)
wswan|WonderSwan (WS)
arc|Arcade (ARC)
neocd|Neo Geo CD (NEOCD)
ss|Sega Saturn (SS)
"

for map in ${mappings}; do
    [ -n "${map}" ] || continue
    src_name="${map%%|*}"
    minui_name="${map##*|}"
    
    src_dir="${ROMS_SRC}/${src_name}"
    [ -d "${src_dir}" ] || continue
    
    # Determine the target directory name
    if [ "${UI_TYPE}" = "minui" ]; then
        target_dir="${DEST_DIR}/Roms/${minui_name}"
    else
        target_dir="${DEST_DIR}/Roms/${src_name}"
    fi
    
    log "Copying ${src_name} -> ${target_dir}..."
    mkdir -p "${target_dir}"
    cp -rp "${src_dir}/." "${target_dir}/"
done

log "ROM installation complete."
