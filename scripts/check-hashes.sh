#!/bin/bash
# Validate SHA-256 and SHA-512 hashes in Buildroot and Alpine configurations
# Max SLOC: 100

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

check_buildroot_hash() {
    local file="$1"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local algo hash_val _rest
        read -r algo hash_val _rest <<< "$line"
        algo=$(echo "$algo" | tr '[:upper:]' '[:lower:]')
        
        if [ "$algo" = "sha256" ]; then
            if ! [[ "$hash_val" =~ ^[0-9a-fA-F]{64}$ ]]; then
                echo "  [ERROR] $file: Invalid SHA-256 hash length/format '$hash_val'"
                ((errors++))
            fi
        elif [ "$algo" = "sha512" ]; then
            if ! [[ "$hash_val" =~ ^[0-9a-fA-F]{128}$ ]]; then
                echo "  [ERROR] $file: Invalid SHA-512 hash length/format '$hash_val'"
                ((errors++))
            fi
        fi
    done < "$file"
}

check_apkbuild() {
    local file="$1"
    local hash_lines
    hash_lines=$(grep -oE '(sha256sums|sha512sums)="[^"]+"' "$file" || true)
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local algo="${line%%=*}"
        local hashes="${line#*=\"}"
        hashes="${hashes%\"}"
        
        while IFS= read -r hline || [ -n "$hline" ]; do
            local hash_val="" _rest=""
            read -r hash_val _rest <<< "$hline"
            [ -z "$hash_val" ] || [ "$hash_val" = "SKIP" ] && continue
            
            if [ "$algo" = "sha256sums" ]; then
                if ! [[ "$hash_val" =~ ^[0-9a-fA-F]{64}$ ]]; then
                    echo "  [ERROR] $file: Invalid SHA-256 string '$hash_val'"
                    ((errors++))
                fi
            elif [ "$algo" = "sha512sums" ]; then
                if ! [[ "$hash_val" =~ ^[0-9a-fA-F]{128}$ ]]; then
                    echo "  [ERROR] $file: Invalid SHA-512 string '$hash_val'"
                    ((errors++))
                fi
            fi
        done <<< "$hashes"
    done <<< "$hash_lines"
}

shopt -s nullglob
br_hashes=("${ROOT_DIR}"/minime/targets/buildroot/external/package/*/*.hash)
echo "Checking ${#br_hashes[@]} Buildroot package .hash file(s)..."
for bh in "${br_hashes[@]}"; do
    check_buildroot_hash "$bh"
done

apkbuilds=("${ROOT_DIR}"/minime/targets/alpine/aports/*/APKBUILD)
echo "Checking ${#apkbuilds[@]} Alpine APKBUILD file(s)..."
for ak in "${apkbuilds[@]}"; do
    check_apkbuild "$ak"
done

if [ "$errors" -gt 0 ]; then
    echo -e "\n[ERROR] Found $errors hash validation error(s)."
    exit 1
fi

echo "Hash validation passed cleanly. All SHA-256 and SHA-512 strings are valid."
exit 0
