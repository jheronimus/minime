#!/bin/sh
# shellcheck shell=sh
# traits.sh: generate /mnt/sdcard/.minime/traits from the immutable
# /usr/share/minime/traits payload bundled at build time.
# Called by both the Alpine OpenRC 'traits' service and Buildroot S09detect-traits wrapper.
# Interface: traits.sh {start|stop}

set -eu

TRAITS_DIR="/usr/share/minime/traits"
TRAITS_FILE="/mnt/sdcard/.minime/traits"

read_match() {
	sed -n "s/^$1=//p" "$2" | head -n 1
}

compatible_matches() {
	expected="$1"
	[ -z "$expected" ] && return 0
	actual=$(tr '\000' '\n' < /proc/device-tree/compatible | head -n 1)
	[ "$actual" = "$expected" ]
}

find_device() {
	model="$1"
	match=""

	for file in "${TRAITS_DIR}"/devices/*.ini; do
		[ -f "$file" ] || continue
		expected_model="$(read_match model "$file")"
		expected_compatible="$(read_match compatible "$file")"
		if [ "$expected_model" = "$model" ] &&
			compatible_matches "$expected_compatible"; then
			[ -z "$match" ] || {
				echo "Multiple Minime trait files match '$model'" >&2
				return 1
			}
			match="$file"
		fi
	done
	[ -n "$match" ] || {
		echo "Unsupported Minime device: '$model'" >&2
		return 1
	}
	printf '%s\n' "$match"
}

write_section() {
	section="$1"
	file="$2"

	printf '[%s]\n' "$section"
	awk '
		/^\[match\]$/ { skip = 1; next }
		/^\[/ { skip = 0; next }
		!skip && /^[A-Za-z0-9_]+=/ { print }
	' "$file"
}

generate_traits() {
	model="$(tr -d '\000\r\n' < /proc/device-tree/model)"
	device_file="$(find_device "$model")"
	tmp="${TRAITS_FILE}.tmp"

	mkdir -p "${TRAITS_FILE%/*}"
	{
		echo "# Minime device traits"
		write_section platform "$TRAITS_DIR/platform.ini"
		echo
		write_section device "$device_file"
	} > "$tmp"
	mv "$tmp" "$TRAITS_FILE"
	echo "Minime traits: ${device_file##*/}"
}

case "${1:-}" in
	start) generate_traits ;;
	stop)  ;;
	*) echo "Usage: $0 {start|stop}" >&2; exit 1 ;;
esac
