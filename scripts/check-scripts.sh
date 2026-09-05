#!/bin/sh
# Validate *.sh scripts: syntax (sh -n / bash -n from shebang), shellcheck
# (auto-detected shell), and executable bit. Excludes upstream/vendored trees.
# Max SLOC: 100

set -eu

cd "$(dirname "$0")/.."

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

find . -type f -name "*.sh" \
	-not -path "*/buildroot/buildroot/*" \
	-not -path "*/build-bootloader-tmp/*" \
	-not -path "*/ui/*" \
	-not -path "*/.git/*" \
	-not -path "*/pkg/*" \
	-not -path "*/downloads/*" \
	-not -path "*/src/yabause/libchdr/*" \
	-not -path "*/src/yabause/yabause/*" \
	-not -path "*/src/drastic/libs/tools/toolchain/*" |
	sort >"$tmp"

while read -r f || [ -n "$f" ]; do
	[ -n "$f" ] || continue
	echo "  sh: $f"
	# Syntax-check with the interpreter declared by the shebang: sh cannot
	# parse bash scripts (arrays, here-strings); bash accepts sh-only scripts.
	interpreter=$(head -n 1 "$f" | sed -n 's|^#!.*[ /]\([a-zA-Z0-9._-]*\) *$|\1|p' | head -n 1)
	case "$interpreter" in
	bash) bash -n "$f" ;;
	*) sh -n "$f" ;;
	esac
	shellcheck --severity=warning "$f"
	if head -n 1 "$f" | grep -q "^#!" && [ ! -x "$f" ]; then
		echo "ERROR: $f has a shebang but no executable bit" >&2
		exit 1
	fi
done <"$tmp"

echo "scripts check passed"
