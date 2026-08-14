#!/bin/sh
# Check required firmware files across kernel configs and Device Trees
# Max SLOC: 100

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

find_fw() {
    fw="$1"
    for d in \
        "${ROOT_DIR}/minime/boards/common/firmware" \
        "${ROOT_DIR}/minime/boards/h700/firmware" \
        "${ROOT_DIR}/minime/boards/rk3326/firmware" \
        "${ROOT_DIR}/minime/boards/rk3566/firmware"
    do
        if [ -f "$d/$fw" ]; then return 0; fi
    done
    return 1
}

check_config() {
    board="$1"
    config="${ROOT_DIR}/minime/boards/${board}/tiny-${board}.config"
    base="${ROOT_DIR}/minime/boards/common/tiny-base.config"

    extra_fw=""
    if [ -f "$base" ]; then
        extra_fw="$extra_fw$(grep -E '^CONFIG_EXTRA_FIRMWARE=' "$base" | cut -d= -f2- | tr -d "\"'" || true)"
        extra_fw="$extra_fw "
    fi
    if [ -f "$config" ]; then
        extra_fw="$extra_fw$(grep -E '^CONFIG_EXTRA_FIRMWARE=' "$config" | cut -d= -f2- | tr -d "\"'" || true)"
    fi

    for fw in $extra_fw; do
        if ! find_fw "$fw"; then
            echo "  [ERROR] [$board] Missing CONFIG_EXTRA_FIRMWARE file(s):"
            echo "    - $fw"
            errors=$((errors + 1))
        fi
    done
}

echo "Checking required firmware files across kernel configs and Device Trees..."

# 1. Check CONFIG_EXTRA_FIRMWARE
check_config "h700"
check_config "rk3326"
check_config "rk3566"

# 2. Check Device Tree firmware-name declarations
tmp_dts=$(mktemp)
trap 'rm -f "$tmp_dts"' EXIT
find "${ROOT_DIR}/minime/boards" -type f \( -name "*.dts" -o -name "*.dtsi" \) > "$tmp_dts"
while IFS= read -r dts || [ -n "$dts" ]; do
    [ -z "$dts" ] && continue
    fws=$(grep -oE 'firmware-name[[:space:]]*=[[:space:]]*"[^"]+"' "$dts" | cut -d'"' -f2 || true)
    for fw in $fws; do
        if ! find_fw "$fw"; then
            echo "  [ERROR] Firmware '$fw' referenced in DTS not found in firmware directories:"
            echo "    - Referenced by ${dts#$ROOT_DIR/}"
            errors=$((errors + 1))
        fi
    done
done < "$tmp_dts"

if [ "$errors" -gt 0 ]; then
    printf '\nFirmware validation failed with %s missing file(s).\n' "$errors"
    exit 1
fi

echo "Firmware validation passed cleanly. All required firmware files are present."
exit 0
