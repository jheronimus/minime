#!/bin/sh
# check-traits.sh: static validation of board trait manifests.
# Validates the sectioned schema (platform.ini + devices/*.ini) and the
# parent= cascade: every required key present, no duplicate matches, no
# empty/obsolete values, and parent references resolve.

set -eu

TRAITS_ROOT="${1:-$(cd "$(dirname "$0")/../minime/boards" && pwd)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
	echo "$*" >&2
	exit 1
}

require_key() {
	key="$1"
	file="$2"
	grep -Eq "^${key}=..*" "$file" || fail "$file: missing $key"
}

# Required keys per section in platform.ini
PLATFORM_KEYS="
screen_backlight_path
screen_backlight_max
screen_blank_path
cpu_governor_path
cpu_clock_path
cpu_clock_menu
cpu_clock_powersave
cpu_clock_normal
cpu_clock_performance
cpu_undervolt_supported
cpu_thermal_path
gpu_device
audio_card
audio_mixer
input_gamepad_device_name
input_power_device_name
input_volume_device_name
input_lid_device_name
input_rumble_device_name
power_battery_sysfs
usb_otg
usb_host_ports
usb_device_mode
usb_controller_mode
storage_sd_node
"

# Required keys per device file
DEVICE_KEYS="
model
compatible
device_id
device_model
screen_width
screen_height
screen_rotation
screen_aspect
screen_refresh_rate
gpu_hdmi_connector
input_touch
wifi_interface
bluetooth_interface
input_axis_lx
input_axis_ly
input_axis_rx
input_axis_ry
input_axis_min
input_axis_center
input_axis_max
"

seen="$(mktemp)"
trap 'rm -f "$seen"' EXIT

# Cross-reference every traits file against the shipped DTB list from the
# Alpine tinykernel APKBUILD. A shipped DTB with no traits (or a traits file
# with no shipped DTB) means the device either won't boot or is unreachable.
APKBUILD="${REPO_ROOT}/minime/targets/alpine/aports/tinykernel/APKBUILD"

# DTB basenames shipped for a board, e.g. "sun50i-h700-anbernic-rg35xx-sp".
# The APKBUILD lists DTB paths without the .dtb suffix (e.g.
# "allwinner/sun50i-h700-anbernic-rg35xx-sp").
dtbs_for_board() {
	board="$1"
	sed -n "/^[[:space:]]*${board})/,/^[[:space:]]*;;/p" "$APKBUILD" |
		grep -Eo '(allwinner|rockchip)/[A-Za-z0-9_-]+' | sed 's|.*/||'
}

# Derive the compatible string a DTB basename implies, e.g.
# "sun50i-h700-anbernic-rg35xx-sp" -> "anbernic,rg35xx-sp".
dtb_to_compatible() {
	basename="$1"
	echo "${basename}" | sed -E 's/^(sun50i-h700|rk3326|rk3566|rk3568)-anbernic-/anbernic,/'
}

for board in h700 rk3326 rk3566; do
	platform="${TRAITS_ROOT}/${board}/traits/platform.ini"
	if [ ! -f "$platform" ]; then
		echo "SKIP: ${board} — no platform.ini" >&2
		continue
	fi

	for key in $PLATFORM_KEYS; do
		require_key "$key" "$platform"
	done

	# Collect this board's shipped DTB compatibles for the cross-check.
	shipped_compat="$(mktemp)"
	dtbs=""
	if [ -f "$APKBUILD" ]; then
		dtbs="$(dtbs_for_board "$board")"
		for dtb in $dtbs; do
			dtb_to_compatible "$dtb" >>"$shipped_compat"
		done
	fi

	# Input trait validation: verify keycodes and device names against kernel authoritative values
	for kv in \
		"key_up=544" "key_down=545" "key_left=546" "key_right=547" \
		"key_a=305" "key_b=304" "key_x=307" "key_y=308" \
		"key_start=315" "key_select=314" "key_menu=316" \
		"key_l1=310" "key_r1=311" "key_l2=312" "key_r2=313" \
		"key_power=116" "key_vol_up=115" "key_vol_down=114"
	do
		k="${kv%%=*}"
		v="${kv#*=}"
		act="$(sed -n "s/^${k}=//p" "$platform" | head -n 1)"
		[ "$act" = "$v" ] || fail "$platform: invalid $k (expected $v, got '$act')"
	done

	case "$board" in
		h700)
			for kv in "input_gamepad_device_name=gpio-keys-gamepad" \
				"input_power_device_name=axp20x-pek" \
				"input_volume_device_name=gpio-keys-volume"; do
				k="${kv%%=*}"
				v="${kv#*=}"
				act="$(sed -n "s/^${k}=//p" "$platform" | head -n 1)"
				[ "$act" = "$v" ] || fail "$platform: invalid $k (expected $v, got '$act')"
			done
			;;
		rk3566)
			for kv in "input_gamepad_device_name=gpio-keys-control" \
				"input_power_device_name=rk805 pwrkey" \
				"input_volume_device_name=gpio-keys-vol"; do
				k="${kv%%=*}"
				v="${kv#*=}"
				act="$(sed -n "s/^${k}=//p" "$platform" | head -n 1)"
				[ "$act" = "$v" ] || fail "$platform: invalid $k (expected $v, got '$act')"
			done
			;;
		rk3326)
			act="$(sed -n "s/^input_power_device_name=//p" "$platform" | head -n 1)"
			[ "$act" = "rk805 pwrkey" ] || fail "$platform: invalid input_power_device_name (expected rk805 pwrkey, got '$act')"
			;;
	esac

	for file in "${TRAITS_ROOT}/${board}"/traits/devices/*.ini; do
		[ -f "$file" ] || continue
		parent="$(sed -n 's/^parent=//p' "$file" | head -n 1)"

		if [ -n "$parent" ]; then
			# Minimal variant inheriting from a base device: only identity
			# + parent link required. The base supplies the rest.
			for key in model compatible device_id device_model; do
				require_key "$key" "$file"
			done
			[ -f "${TRAITS_ROOT}/${board}/traits/devices/${parent}.ini" ] ||
				fail "$file: unknown parent '$parent'"
			[ "$parent" != "${file##*/}" ] || fail "$file: parent cannot be itself"
		else
			for key in $DEVICE_KEYS; do
				require_key "$key" "$file"
			done

			# Validate analog stick axis codes & ranges
			lx="$(sed -n 's/^input_axis_lx=//p' "$file" | head -n 1)"
			ly="$(sed -n 's/^input_axis_ly=//p' "$file" | head -n 1)"
			rx="$(sed -n 's/^input_axis_rx=//p' "$file" | head -n 1)"
			ry="$(sed -n 's/^input_axis_ry=//p' "$file" | head -n 1)"
			amin="$(sed -n 's/^input_axis_min=//p' "$file" | head -n 1)"
			actr="$(sed -n 's/^input_axis_center=//p' "$file" | head -n 1)"
			amax="$(sed -n 's/^input_axis_max=//p' "$file" | head -n 1)"

			if [ "$lx" != "na" ]; then
				[ "$lx" = "0" ] || fail "$file: invalid input_axis_lx '$lx' (expected 0)"
				[ "$ly" = "1" ] || fail "$file: invalid input_axis_ly '$ly' (expected 1)"
				if [ "$rx" != "na" ]; then
					[ "$rx" = "3" ] || fail "$file: invalid input_axis_rx '$rx' (expected 3)"
					[ "$ry" = "4" ] || fail "$file: invalid input_axis_ry '$ry' (expected 4)"
				fi
				case "$board" in
					h700|rk3326)
						[ "$amin" = "0" ] && [ "$actr" = "2048" ] && [ "$amax" = "4096" ] ||
							fail "$file: invalid axis range (expected min=0 center=2048 max=4096, got min=$amin center=$actr max=$amax)"
						;;
					rk3566)
						[ "$amin" = "15" ] && [ "$actr" = "519" ] && [ "$amax" = "1023" ] ||
							fail "$file: invalid axis range (expected min=15 center=519 max=1023, got min=$amin center=$actr max=$amax)"
						;;
				esac
			else
				[ "$ly" = "na" ] && [ "$rx" = "na" ] && [ "$ry" = "na" ] &&
				[ "$amin" = "na" ] && [ "$actr" = "na" ] && [ "$amax" = "na" ] ||
					fail "$file: non-stick device must set all axis traits to 'na'"
			fi
		fi

		# Duplicate [match] detection
		match="$(sed -n 's/^model=//p; s/^compatible=//p' "$file" | paste -sd '|' -)"
		if grep -Fqx "$match" "$seen"; then
			fail "$file: duplicate match $match"
		fi
		echo "$match" >>"$seen"

		# Obsolete or empty trait values (na allowed only for known-optional)
		if grep -Eq '^(has_|button_layout=)|=$' "$file" "$platform"; then
			fail "$file: obsolete or empty trait"
		fi

		# Every non-parent traits file must correspond to a shipped DTB.
		if [ -f "$APKBUILD" ] && [ -z "$parent" ]; then
			compat="$(sed -n 's/^compatible=//p' "$file" | head -n 1)"
			shipped_ok=""
			if [ -n "$compat" ]; then
				if grep -Fxq "$compat" "$shipped_compat"; then
					shipped_ok=1
				fi
			fi
			if [ -n "$compat" ] && [ -z "$shipped_ok" ]; then
				fail "$file: no shipped DTB for compatible '$compat'"
			fi
		fi
	done
	rm -f "$shipped_compat"

	# Every shipped DTB must have a traits file. Parent-less traits whose
	# compatible is implied by a shipped DTB were counted above; here we catch
	# shipped DTBs with no traits at all.
	if [ -n "$dtbs" ]; then
		for dtb in $dtbs; do
			compat="$(dtb_to_compatible "$dtb")"
			if ! grep -Fqx "$compat" "$seen" && ! grep -q "compatible=${compat}\$" \
				"${TRAITS_ROOT}/${board}"/traits/devices/*.ini 2>/dev/null; then
				fail "board ${board}: shipped DTB ${dtb} has no traits file"
			fi
		done
	fi
done

echo "traits check passed"
