#!/bin/sh

# Board-specific post-build script for RK3326
# Installs external USB Wi-Fi and Bluetooth firmware from the board folder

set -eu

FW_SRC_DIR="${BR_BOARD_DIR}/firmware"

if [ -d "${FW_SRC_DIR}" ]; then
	echo "Installing RK3326-specific USB dongle firmware..."
	find "${FW_SRC_DIR}" -type f | while read -r fwfile; do
		# Extract path relative to the board's firmware folder
		rel="${fwfile#${FW_SRC_DIR}/}"
		target_path="${TARGET_DIR}/lib/firmware/${rel}"

		# Ensure destination folder exists and copy the file
		mkdir -p "$(dirname "${target_path}")"
		cp -f "${fwfile}" "${target_path}"
	done
else
	echo "Warning: RK3326 firmware source directory not found at ${FW_SRC_DIR}"
fi
