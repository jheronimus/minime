#!/bin/sh
# Validate APKBUILD files: syntax (sh -n) and shellcheck targeting ash.
# SC2154 (abuild-injected vars) is suppressed via inline directive in each file.
# No shebang or executable check — abuild sources them directly.
# Max SLOC: 100

set -eu

cd "$(dirname "$0")/.."

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

find packages/components/alpine/aports -name "APKBUILD" -not -path "*/pkg/*" | sort >"$tmp"

while read -r f || [ -n "$f" ]; do
	[ -n "$f" ] || continue
	echo "  apkbuild: $f"
	sh -n "$f"
	shellcheck --shell=sh --severity=warning "$f"
done <"$tmp"

echo "apkbuilds check passed"
