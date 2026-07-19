#!/bin/sh

set -eu

ROOT="${1:-$(dirname "$0")/..}"
ROOT="$(cd "$ROOT" && pwd)"
seen="$(mktemp)"
trap 'rm -f "$seen"' EXIT

require_key() {
	key="$1"
	file="$2"
	grep -Eq "^${key}=..*" "$file" || {
		echo "$file: missing $key" >&2
		exit 1
	}
}

for board in h700 rk3326 rk3566; do
	platform="$ROOT/$board/traits/platform.ini"
	require_key video_device "$platform"
	require_key backlight_path "$platform"
	require_key input_gamepad_device_name "$platform"
	require_key input_power_device_name "$platform"
	require_key input_volume_device_name "$platform"

	for file in "$ROOT/$board"/traits/devices/*.ini; do
		for key in model compatible device_id device_model screen_width \
			screen_height screen_rotation wifi_interface bluetooth_adapter \
			hdmi_state_path battery_capacity_path charger_online_path \
			lid_switch_path rumble_path power_led_path axis_lx axis_ly \
			axis_rx axis_ry axis_min axis_center axis_max; do
			require_key "$key" "$file"
		done
		match="$(sed -n 's/^model=//p; s/^compatible=//p' "$file" |
			paste -sd '|' -)"
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
