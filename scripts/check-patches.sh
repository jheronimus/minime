#!/bin/bash
# Check for unreferenced/orphaned patch files
# Max SLOC: 100

set -euo pipefail
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

PATCH_DIRS=(
    "${ROOT_DIR}/minime/boards"
    "${ROOT_DIR}/minime/uboot"
    "${ROOT_DIR}/minime/targets/alpine/aports"
    "${ROOT_DIR}/minime/targets/buildroot/external/package"
)

tmp_patch=$(mktemp)
trap 'rm -f "$tmp_patch" "$tmp_cache"' EXIT
patch_files=()
for d in "${PATCH_DIRS[@]}"; do
    if [ -d "$d" ]; then
        find "$d" -type f -name "*.patch" -print0 > "$tmp_patch"
        while IFS= read -r -d '' p || [ -n "$p" ]; do
            [ -z "$p" ] && continue
            patch_files+=("$p")
        done < "$tmp_patch"
    fi
done

if [ ${#patch_files[@]} -eq 0 ]; then
    echo "No patch files found to check."
    exit 0
fi

echo "Checking ${#patch_files[@]} patch file(s) for references in build manifests..."

tmp_cache=$(mktemp)
find "${ROOT_DIR}/minime" "${ROOT_DIR}/scripts" "${ROOT_DIR}/.github" -type f \
    \( -name "APKBUILD" -o -name "Makefile" -o -name "series" -o -name "*.mk" -o -name "*.sh" -o -name "*.yml" -o -name "*.config" \) \
    -exec cat {} + > "$tmp_cache" 2>/dev/null || true

for p in "${patch_files[@]}"; do
    name="$(basename "$p")"
    rel_path="${p#$ROOT_DIR/}"
    
    if ! grep -qF -e "$name" -e "$rel_path" "$tmp_cache"; then
        parent="$(basename "$(dirname "$p")")"
        if [[ "$parent" == "patches" || "$parent" == "linux" || "$parent" == "uboot" || "$parent" == "atf" || "$parent" == "sdl2" ]]; then
            if ! grep -qF -e "patches" -e "*.patch" "$tmp_cache"; then
                echo "  [ERROR] Found unreferenced/orphaned patch: $rel_path"
                ((errors++))
            fi
        else
            echo "  [ERROR] Found unreferenced/orphaned patch: $rel_path"
            ((errors++))
        fi
    fi
done

if [ "$errors" -gt 0 ]; then
    echo -e "\n[ERROR] Found $errors unreferenced/orphaned patch file(s)."
    exit 1
fi

echo "Patch validation passed cleanly. All patches are properly referenced."
exit 0
