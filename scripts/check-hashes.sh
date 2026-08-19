#!/bin/sh
# Validate SHA-256 and SHA-512 hashes in Buildroot and Alpine configurations
# Max SLOC: 100

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

is_hex_len() {
    [ "${#1}" -eq "$2" ] || return 1
    case "$1" in
    *[!0-9a-fA-F]*) return 1 ;;
    esac
    return 0
}

check_buildroot_hash() {
    file="$1"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ""|\#*) continue ;; esac
        set -- $line
        algo="${1:-}"
        hash_val="${2:-}"
        algo=$(echo "$algo" | tr '[:upper:]' '[:lower:]')

        case "$algo" in
        sha256)
            if ! is_hex_len "$hash_val" 64; then
                echo "  [ERROR] $file: Invalid SHA-256 hash length/format '$hash_val'"
                errors=$((errors + 1))
            fi
            ;;
        sha512)
            if ! is_hex_len "$hash_val" 128; then
                echo "  [ERROR] $file: Invalid SHA-512 hash length/format '$hash_val'"
                errors=$((errors + 1))
            fi
            ;;
        esac
    done < "$file"
}

check_apkbuild() {
    file="$1"
    hash_lines=$(grep -oE '(sha256sums|sha512sums)="[^"]+"' "$file" || true)

    tmp_lines=$(mktemp)
    tmp_hashes=$(mktemp)
    trap 'rm -f "$tmp_lines" "$tmp_hashes"' EXIT
    printf '%s\n' "$hash_lines" > "$tmp_lines"

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        algo="${line%%=*}"
        hashes="${line#*=\"}"
        hashes="${hashes%\"}"

        printf '%s\n' "$hashes" > "$tmp_hashes"
        while IFS= read -r hline || [ -n "$hline" ]; do
            set -- $hline
            hash_val="${1:-}"
            [ -z "$hash_val" ] || [ "$hash_val" = "SKIP" ] && continue

            case "$algo" in
            sha256sums)
                if ! is_hex_len "$hash_val" 64; then
                    echo "  [ERROR] $file: Invalid SHA-256 string '$hash_val'"
                    errors=$((errors + 1))
                fi
                ;;
            sha512sums)
                if ! is_hex_len "$hash_val" 128; then
                    echo "  [ERROR] $file: Invalid SHA-512 string '$hash_val'"
                    errors=$((errors + 1))
                fi
                ;;
            esac
        done < "$tmp_hashes"
    done < "$tmp_lines"
    rm -f "$tmp_lines" "$tmp_hashes"
}

tmp_br=$(mktemp)
tmp_ak=$(mktemp)
trap 'rm -f "$tmp_br" "$tmp_ak"' EXIT

find "${ROOT_DIR}/packages/components/buildroot/external/package" -type f -name '*.hash' > "$tmp_br"
br_count=$(wc -l < "$tmp_br")
echo "Checking $br_count Buildroot package .hash file(s)..."
while IFS= read -r bh || [ -n "$bh" ]; do
    [ -n "$bh" ] && check_buildroot_hash "$bh"
done < "$tmp_br"

find "${ROOT_DIR}/packages/components/alpine/aports" -type f -name 'APKBUILD' > "$tmp_ak"
ak_count=$(wc -l < "$tmp_ak")
echo "Checking $ak_count Alpine APKBUILD file(s)..."
while IFS= read -r ak || [ -n "$ak" ]; do
    [ -n "$ak" ] && check_apkbuild "$ak"
done < "$tmp_ak"

if [ "$errors" -gt 0 ]; then
    printf '\n[ERROR] Found %s hash validation error(s).\n' "$errors"
    exit 1
fi

echo "Hash validation passed cleanly. All SHA-256 and SHA-512 strings are valid."
exit 0
