# Minime shell profile.  Loaded by /etc/profile for login shells only.
# Sets up the SD-card layout contract so any user-issued shell is identical
# to what MinUI/Allium expect at runtime.

export SDCARD_PATH=/mnt/sdcard
export HOME="${SDCARD_PATH}"
export ROMS_PATH="${SDCARD_PATH}/roms"
export SAVES_PATH="${SDCARD_PATH}/saves"
export BIOS_PATH="${SDCARD_PATH}/bios"
export CORES_PATH="${SDCARD_PATH}/.cores"
export UI_PATH="${SDCARD_PATH}/.ui"
