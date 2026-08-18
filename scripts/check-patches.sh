#!/bin/sh
# Check for unreferenced/orphaned patch files
# Max SLOC: 100

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

tmp_patch=$(mktemp)
tmp_cache=""
trap 'rm -f "$tmp_patch" "$tmp_cache"' EXIT

: >"$tmp_patch"
for d in \
	"${ROOT_DIR}/minime/boards" \
	"${ROOT_DIR}/minime/uboot" \
	"${ROOT_DIR}/minime/build/cores" \
	"${ROOT_DIR}/minime/ui/muos" \
	"${ROOT_DIR}/minime/targets/alpine/aports" \
	"${ROOT_DIR}/minime/targets/buildroot/external/package"; do
	if [ -d "$d" ]; then
		find "$d" -type f -name "*.patch" >>"$tmp_patch"
	fi
done

if [ ! -s "$tmp_patch" ]; then
	echo "No patch files found to check."
	exit 0
fi

patch_count=$(wc -l <"$tmp_patch")
echo "Checking $patch_count patch file(s) for references in build manifests..."

tmp_cache=$(mktemp)
find "${ROOT_DIR}/minime" "${ROOT_DIR}/scripts" "${ROOT_DIR}/.github" -type f \
	\( -name "APKBUILD" -o -name "Makefile" -o -name "series" -o -name "*.mk" -o -name "*.sh" -o -name "*.yml" -o -name "*.config" -o -name "manifest" \) \
	-exec cat {} + >"$tmp_cache" 2>/dev/null || true

while IFS= read -r p || [ -n "$p" ]; do
	[ -z "$p" ] && continue
	name="$(basename "$p")"
	rel_path="${p#$ROOT_DIR/}"

	if ! grep -qF -e "$name" -e "$rel_path" "$tmp_cache"; then
		parent="$(basename "$(dirname "$p")")"
		case "$parent" in
		patches | linux | uboot | atf | sdl2)
			if ! grep -qF -e "patches" -e "*.patch" "$tmp_cache"; then
				echo "  [ERROR] Found unreferenced/orphaned patch: $rel_path"
				errors=$((errors + 1))
			fi
			;;
		*)
			echo "  [ERROR] Found unreferenced/orphaned patch: $rel_path"
			errors=$((errors + 1))
			;;
		esac
	fi
done <"$tmp_patch"

if [ "$errors" -gt 0 ]; then
	printf '\n[ERROR] Found %s unreferenced/orphaned patch file(s).\n' "$errors"
	exit 1
fi

echo "Patch validation passed cleanly. All patches are properly referenced."
exit 0
