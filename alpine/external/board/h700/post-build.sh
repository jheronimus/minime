#!/bin/sh
set -eu

# Copy wifi/bt firmware from H700 board directory
mkdir -p "${TARGET_DIR}/lib/firmware/rtw88"
mkdir -p "${TARGET_DIR}/lib/firmware/rtl_bt"
cp -f "${BOARD_DIR}/firmware/rtw88/rtw8821c_fw.bin" "${TARGET_DIR}/lib/firmware/rtw88/"
cp -f "${BOARD_DIR}/firmware/rtl_bt/rtl8821cs_fw.bin" "${TARGET_DIR}/lib/firmware/rtl_bt/"
cp -f "${BOARD_DIR}/firmware/rtl_bt/rtl8821cs_config.bin" "${TARGET_DIR}/lib/firmware/rtl_bt/"
