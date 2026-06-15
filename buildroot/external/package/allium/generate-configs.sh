#!/bin/sh

set -eu

input="$1"
output="$2"
cores="$output/cores.toml"
consoles="$output/consoles.toml"
seen="$output/.cores.seen"

mkdir -p "$output"
: > "$cores"
: > "$consoles"
: > "$seen"
trap 'rm -f "$seen"' EXIT

while IFS='|' read -r folder core core_name system_name; do
	folder="$(printf '%s' "$folder" | xargs)"
	[ -n "$folder" ] || continue
	case "$folder" in \#*) continue ;; esac
	core="$(printf '%s' "$core" | xargs)"
	core_name="$(printf '%s' "$core_name" | xargs)"
	system_name="$(printf '%s' "$system_name" | xargs)"
	core_id="${core%_libretro.so}"

	if ! grep -Fqx "$core_id" "$seen"; then
		printf '[cores.%s]\nretroarch = "%s"\nname = "%s"\n\n' \
			"$core_id" "$core_id" "$core_name" >> "$cores"
		printf '%s\n' "$core_id" >> "$seen"
	fi
	printf '[[consoles]]\nname = "%s"\ncores = ["%s"]\npatterns = ["%s"]\n\n' \
		"$system_name" "$core_id" "$folder" >> "$consoles"
done < "$input"
