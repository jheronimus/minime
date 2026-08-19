#!/bin/sh
# Validate OpenRC init.d scripts: shellcheck targeting ash.
# SC2034 (openrc-run framework globals) is suppressed via inline directive.
# Executable permission is required — OpenRC runs them directly.
# Max SLOC: 100

set -eu

cd "$(dirname "$0")/.."

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

find packages/components/boards -path "*/etc/init.d/*" -type f -not -path "*/pkg/*" | sort >"$tmp"

while read -r f || [ -n "$f" ]; do
	[ -n "$f" ] || continue
	echo "  openrc: $f"
	shellcheck --shell=sh --severity=warning "$f"
	if [ ! -x "$f" ]; then
		echo "ERROR: $f is not executable" >&2
		exit 1
	fi
done <"$tmp"

echo "openrc check passed"
