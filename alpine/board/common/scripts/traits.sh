#!/bin/sh
# shellcheck shell=sh
# traits.sh: generate /mnt/sdcard/.minime/traits from the immutable
# /usr/share/minime/traits payload bundled at build time.
# Called by both the Alpine OpenRC 'traits' service and Buildroot S09detect-traits wrapper.
# Interface: traits.sh {start|stop}

set -eu

TRAITS_DIR="/usr/share/minime/traits"
TRAITS_FILE="/mnt/sdcard/.minime/traits"

# Match current hardware against device trait manifests; prints the matching .ini path
find_device() {
	model="$(tr -d '\000\r\n' < /proc/device-tree/model)"
	actual_compat="$(tr '\000' '\n' < /proc/device-tree/compatible 2>/dev/null | head -n 1 || true)"
	match=""

	for file in "${TRAITS_DIR}"/devices/*.ini; do
		[ -f "$file" ] || continue
		expected_model="$(read_match model "$file")"
		expected_compat="$(read_match compatible "$file")"
		if [ "$expected_model" = "$model" ] &&
		   { [ -z "$expected_compat" ] || [ "$expected_compat" = "$actual_compat" ]; }; then
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

# Ensure a valid, up-to-date traits file exists at boot:
#   - missing       -> generate
#   - wrong device  -> regenerate (SD card moved between devices)
#   - invalid keys  -> regenerate (truncated or corrupted write)
check_traits() {
	device_file="$(find_device)" || exit 1
	expected_id="$(read_match device_id "$device_file")"

	if [ ! -f "$TRAITS_FILE" ]; then
		generate_traits "$device_file"
	elif [ "$(read_match device_id "$TRAITS_FILE")" != "$expected_id" ]; then
		generate_traits "$device_file"
	elif ! require_key video_device "$TRAITS_FILE" 2>/dev/null || \
	     ! require_key device_id "$TRAITS_FILE" 2>/dev/null; then
		generate_traits "$device_file"
	fi
}

# Write platform and device traits into TRAITS_FILE atomically
generate_traits() {
	device_file="${1:-$(find_device)}"
	tmp="${TRAITS_FILE}.tmp"

	mkdir -p "${TRAITS_FILE%/*}"
	{
		echo "# Minime device traits"
		write_section platform "$TRAITS_DIR/platform.ini"
		echo
		write_section device "$device_file"
	} > "$tmp"
	mv "$tmp" "$TRAITS_FILE"

	if [ -d /mnt/sdcard ]; then
		model="$(tr -d '\000\r\n' < /proc/device-tree/model 2>/dev/null || true)"
		printf '[TRAITS %s] Model: %s, Device file: %s\n' \
			"$(date -u +'%T' 2>/dev/null || true)" "$model" "${device_file##*/}" >> /mnt/sdcard/boot.log 2>/dev/null || true
		sync 2>/dev/null || true
	fi

	echo "Minime traits: ${device_file##*/}"
}

# Static lint check for all board trait manifests in the repo
validate_traits() {
	root="${1:-}"
	if [ -z "$root" ]; then
		root="$(cd "$(dirname "$0")/../.." && pwd)"
	fi
	seen="$(mktemp)"
	trap 'rm -f "$seen"' EXIT

	for board in h700 rk3326 rk3566; do
		platform="$root/$board/traits/platform.ini"
		require_key video_device "$platform"
		require_key backlight_path "$platform"
		require_key input_gamepad_device_name "$platform"
		require_key input_power_device_name "$platform"
		require_key input_volume_device_name "$platform"

		for file in "$root/$board"/traits/devices/*.ini; do
			for key in model compatible device_id device_model screen_width \
				screen_height screen_rotation wifi_interface bluetooth_adapter \
				hdmi_state_path battery_capacity_path charger_online_path \
				lid_switch_path rumble_path power_led_path axis_lx axis_ly \
				axis_rx axis_ry axis_min axis_center axis_max; do
				require_key "$key" "$file"
			done
			match="$(sed -n 's/^model=//p; s/^compatible=//p' "$file" | paste -sd '|' -)"
			if grep -Fqx "$match" "$seen"; then
				echo "$file: duplicate match $match" >&2
				exit 1
			fi
			echo "$match" >>"$seen"
			if grep -Eq '^(has_|button_layout=)|=$' "$file" "$platform"; then
				echo "$file: obsolete or empty trait" >&2
				exit 1
			fi
		done
	done

	echo "traits check passed"
}

# Helper: Extract value for a key from an INI file
read_match() {
	sed -n "s/^$1=//p" "$2" | head -n 1
}

# Helper: Format an INI section, skipping the [match] block
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

# Helper: Verify a required key exists and is non-empty in an INI file
require_key() {
	key="$1"
	file="$2"
	grep -Eq "^${key}=..*" "$file" || {
		echo "$file: missing $key" >&2
		exit 1
	}
}

case "${1:-}" in
	start) check_traits ;;
	stop)  ;;
	check) validate_traits "${2:-}" ;;
	*) echo "Usage: $0 {start|stop|check}" >&2; exit 1 ;;
esac
