#!/bin/sh
# Enforce the build-convention rules from AGENTS.md:
#   - mkimage.sh / mkupdate.sh / genassets.sh are packaging-only: no compilation.
#   - build.sh is compilation-only: no packaging.
# These rules have no other enforcement (the pipeline fails only at make time),
# so catch violations statically at commit time.
# Max SLOC: 100

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

COMPILE_RE='^\s*(make |make$|gcc |gcc$|g\+\+ |clang |configure |cmake |abuild |apk add|cargo )'
PACKAGE_RE='^\s*(genimage|mcopy|mkdosfs|mkfs\.|dd )'

check_no_compile() {
	file="$1"
	if [ -f "$file" ] && grep -qE "$COMPILE_RE" "$file"; then
		echo "ERROR: $file contains compilation logic (packaging-only script)" >&2
		errors=$((errors + 1))
	fi
}

check_no_package() {
	file="$1"
	if [ -f "$file" ] && grep -qE "$PACKAGE_RE" "$file"; then
		echo "ERROR: $file contains packaging logic (compilation-only script)" >&2
		errors=$((errors + 1))
	fi
}

check_no_compile "$ROOT_DIR/minime/build/mkimage.sh"
check_no_compile "$ROOT_DIR/minime/build/mkupdate.sh"
check_no_compile "$ROOT_DIR/minime/build/genassets.sh"

for target in alpine buildroot; do
	check_no_package "$ROOT_DIR/minime/targets/${target}/scripts/build.sh"
done

if [ "$errors" -eq 0 ]; then
	echo "build flow check passed"
else
	exit 1
fi
