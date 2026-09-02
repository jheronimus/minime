#!/bin/sh
# check-traits.sh: static validation of board trait manifests.
# Structural validation (schema, parent= cascade, DTB cross-reference,
# duplicate matches, obsolete values) is delegated to traits-gen, which owns
# the registry. This script keeps only the input/axis semantic checks that
# verify keycodes and device names against kernel-authoritative values.

set -eu

TRAITS_ROOT="${1:-$(cd "$(dirname "$0")/../packages/components/boards" && pwd)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAITS_GEN="${REPO_ROOT}/packages/image/gentraits.sh"

fail() {
	echo "$*" >&2
	exit 1
}

for board in h700 rk3326 rk3566; do
	platform="${TRAITS_ROOT}/${board}/traits/platform.ini"
	if [ ! -f "$platform" ]; then
		echo "SKIP: ${board} — no platform.ini" >&2
		continue
	fi

	"$TRAITS_GEN" check "$board" || fail "board ${board}: traits-gen check failed"

	# Input trait validation: verify keycodes and device names against kernel authoritative values
	for kv in \
		"key_up=544" "key_down=545" "key_left=546" "key_right=547" \
		"key_a=305" "key_b=304" "key_x=307" "key_y=308" \
		"key_start=315" "key_select=314" "key_menu=316" \
		"key_l1=310" "key_r1=311" "key_l2=312" "key_r2=313" \
		"key_power=116" "key_vol_up=115" "key_vol_down=114"; do
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
		[ -n "$parent" ] && continue

		# Validate analog stick axis codes & ranges
		lx="$(sed -n 's/^input_axis_lx=//p' "$file" | head -n 1)"
		ly="$(sed -n 's/^input_axis_ly=//p' "$file" | head -n 1)"
		rx="$(sed -n 's/^input_axis_rx=//p' "$file" | head -n 1)"
		ry="$(sed -n 's/^input_axis_ry=//p' "$file" | head -n 1)"
		amin="$(sed -n 's/^input_axis_min=//p' "$file" | head -n 1)"
		actr="$(sed -n 's/^input_axis_center=//p' "$file" | head -n 1)"
		amax="$(sed -n 's/^input_axis_max=//p' "$file" | head -n 1)"
		stick="$(sed -n 's/^input_stick_device_name=//p' "$file" | head -n 1)"

		if [ "$lx" != "na" ]; then
			[ "$lx" = "0" ] || fail "$file: invalid input_axis_lx '$lx' (expected 0)"
			[ "$ly" = "1" ] || fail "$file: invalid input_axis_ly '$ly' (expected 1)"
			[ "$stick" = "adc-joystick" ] ||
				fail "$file: stick device must set input_stick_device_name=adc-joystick (got '$stick')"
			if [ "$rx" != "na" ]; then
				[ "$rx" = "3" ] || fail "$file: invalid input_axis_rx '$rx' (expected 3)"
				[ "$ry" = "4" ] || fail "$file: invalid input_axis_ry '$ry' (expected 4)"
			fi
			case "$board" in
			h700 | rk3326)
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
			[ "$stick" = "na" ] ||
				fail "$file: non-stick device must set input_stick_device_name=na (got '$stick')"
		fi
	done
done

echo "traits check passed"

# --- Consumer parity guard ---------------------------------------------------
# The registry is the single source of truth for the emitted traits file.
# Every key the registry can emit must be understood by every UI parser
# (Allium traits.rs, MinUI traits.c); otherwise the parser rejects or
# mis-parses the merged file at runtime. [dts]/[match]/parent keys are
# generation metadata and are never emitted.

ALLIUM_TRAITS="${REPO_ROOT}/packages/ui/allium/crates/common/src/platform/minime/traits.rs"
MINUI_TRAITS="${REPO_ROOT}/packages/ui/minui/workspace/minime/platform/traits.c"

# Keys the merged runtime file can contain (registry minus meta keys).
emitted_keys() {
	cat "${TRAITS_ROOT}"/*/traits/platform.ini "${TRAITS_ROOT}"/*/traits/devices/*.ini |
		grep -E '^[A-Za-z0-9_]+=' |
		grep -vE '^(parent|model|compatible|base|dtb|panel|panel_supply|panel_rotation|compat_parent)=' |
		cut -d= -f1 | sort -u
	# Dynamically resolved by /etc/init.d/traits at boot
	echo "gpu_hdmi_state_path"
}

# Key set a parser understands, one per line.
allium_keys() {
	awk '/^const KNOWN_KEYS/,/^];/' "$ALLIUM_TRAITS" | grep -oE '"[a-z0-9_]+"' | tr -d '"'
}

minui_keys() {
	awk '/^static const TraitField TRAIT_FIELDS/,/^};/' "$MINUI_TRAITS" |
		grep -oE '"[a-z0-9_]+"' | tr -d '"'
}

# Write emitted keys to a temp file so the while loop is not in a pipe subshell.
# (In POSIX sh, 'cmd | while read' runs while in a subshell; 'read' returning 1
# at EOF then propagates as the loop's exit code, falsely triggering '|| exit 1'.)
_keys_tmp="$(mktemp)"
emitted_keys > "$_keys_tmp"
while IFS= read -r key; do
	[ -f "$ALLIUM_TRAITS" ] && { allium_keys | grep -Fxq "$key" || {
		echo "registry key '$key' is missing from Allium traits.rs KNOWN_KEYS" >&2
		exit 1
	}; }
done < "$_keys_tmp"

# Verify MinUI only declares keys emitted by the registry
if [ -f "$MINUI_TRAITS" ]; then
	for key in $(minui_keys); do
		grep -Fxq "$key" "$_keys_tmp" || {
			echo "MinUI trait key '$key' is not emitted by any registry profile" >&2
			exit 1
		}
	done
fi
rm -f "$_keys_tmp"

echo "consumer parity check passed"
