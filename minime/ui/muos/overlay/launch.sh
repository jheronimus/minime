#!/bin/sh
# Minime -> MuOS bridge launcher.
#
# Boot contract: Minime's init.d/ui starts this script, which must stay alive
# as the parent of muxfrontend (upstream uses PDEATHSIG, so a live parent is
# required). Responsibilities, in order:
#   1. Derive every MuOS device/config/* key-file from the Minime traits
#      (the single source of truth). The fork's C code is byte-identical to
#      upstream, so ALL device knowledge flows through these files.
#   2. Seed first-run settings (skip the New User Guide).
#   3. Populate /run/muos (runtime state + persistent storage view).
#   4. Run the frontend lifecycle loop.
set -eu

MUOS_ROOT="/mnt/sdcard/.muos"
MUOS_DATA="/mnt/sdcard/MUOS"
TRAITS="/mnt/sdcard/.minime/traits"
DEV_CFG="${MUOS_ROOT}/device/config"
RUN_MUOS="/run/muos"

export LD_LIBRARY_PATH="${MUOS_ROOT}/bin/lib:${MUOS_ROOT}/bin:${LD_LIBRARY_PATH:-}"
export PATH="${MUOS_ROOT}/bin:${MUOS_ROOT}/script/mux:${PATH:-}"
export HOME="/mnt/sdcard"
export XDG_RUNTIME_DIR="/run"

# ---- trait accessors ---------------------------------------------------------
trait() { sed -n "s/^$1=//p" "$TRAITS" 2>/dev/null | head -n 1; }
has() { [ -n "$1" ] && [ "$1" != "na" ]; }
is1() { [ "$1" = "1" ]; }

# ---- runtime dirs + persistent storage view ----------------------------------
mkdir -p /run/muos /tmp/muos
mkdir -p "${MUOS_DATA}"
ln -sfn "${MUOS_DATA}" "${RUN_MUOS}/storage"

# Upstream muOS init creates /opt/muos -> payload root; the internal scripts and
# device helpers hardcode /opt/muos paths, so mirror it here.
[ -L /opt/muos ] || ln -sfn "${MUOS_ROOT}" /opt/muos 2>/dev/null || true

# ---- device/config generation -------------------------------------------------
# mkfile DIR KEY VALUE: create only when absent, never clobber runtime writes.
mkfile() {
	[ -d "${DEV_CFG}/$1" ] || mkdir -p "${DEV_CFG}/$1"
	[ -f "${DEV_CFG}/$1/$2" ] || printf '%s\n' "$3" >"${DEV_CFG}/$1/$2"
}
# mkfile_force DIR KEY VALUE: always refresh (used for trait-derived truth).
mkfile_force() {
	[ -d "${DEV_CFG}/$1" ] || mkdir -p "${DEV_CFG}/$1"
	printf '%s\n' "$3" >"${DEV_CFG}/$1/$2"
}

# CRC-16/ARC (poly 0xA001, init 0) — identical to SDL_crc16. Prints 4 hex
# chars, little-endian byte order (the SDL evdev GUID stores it LE).
crc16_le() {
	s="$1"
	crc=0
	i=0
	len=${#s}
	while [ "$i" -lt "$len" ]; do
		c=$(printf '%s' "$s" | cut -c$((i + 1)))
		i=$((i + 1))
		byte=$(printf '%d' "'$c")
		r=$((byte ^ (crc & 255)))
		n=0
		while [ "$n" -lt 8 ]; do
			if [ $((r & 1)) -ne 0 ]; then
				r=$(((r >> 1) ^ 0xA001))
			else
				r=$((r >> 1))
			fi
			n=$((n + 1))
		done
		crc=$(((crc >> 8) ^ r))
	done
	printf '%02x%02x' $((crc & 255)) $(((crc >> 8) & 255))
}

# Ascending-sorted set of evdev button codes the gamepad device reports
# (SDL 2.30 ranks buttons in ascending keycode order: BTN_JOYSTICK..KEY_MAX
# then 0..BTN_JOYSTICK; all gamepad keys are >= BTN_JOYSTICK, so ascending).
gpad_codes() {
	{
		trait key_up
		trait key_down
		trait key_left
		trait key_right
		trait key_a
		trait key_b
		trait key_x
		trait key_y
		trait key_c
		trait key_z
		trait key_l1
		trait key_r1
		trait key_l2
		trait key_r2
		trait key_l3
		trait key_r3
		trait key_select
		trait key_start
		trait key_menu
	} | grep -E '^[0-9]+$' | sort -n
}

# SDL button index for a trait key: rank among the gamepad's enabled buttons.
btn_idx() {
	code=$(trait "$1")
	[ -n "$code" ] && [ "$code" != "na" ] || {
		echo 0
		return
	}
	n=0
	for c in $(gpad_codes); do
		[ "$c" = "$code" ] && {
			echo "$n"
			return
		}
		n=$((n + 1))
	done
	echo 0
}

# Read the evdev device's kernel hardware IDs (bus/vendor/product/version) from
# sysfs, matched by device name. Prints "bus vendor product version" in hex,
# or the fallbacks when the device can't be found.
# SDL_CreateJoystickGUID for a Linux evdev device uses exactly these four
# values from the kernel's input_id, so the GUID must match what SDL computes.
device_ids() {
	name="$1"
	for ev in /sys/class/input/event*/device; do
		[ -r "$ev/name" ] || continue
		[ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] || continue
		prod=$(sed -n 's/^PRODUCT=//p' "$ev/uevent" 2>/dev/null | head -n1)
		[ -n "$prod" ] || continue
		IFS=/ read -r bus vendor product version <<EOF
$prod
EOF
		printf '0x%s 0x%s 0x%s 0x%s\n' "$bus" "$vendor" "$product" "$version"
		return 0
	done
	printf '0x19 0x0001 0x0001 0x0100\n'
}

# build_map NAME IS_GAMEPAD -> full SDL gamecontroller mapping string.
# GUID layout (SDL_CreateJoystickGUID, LE uint16 slots):
#   [0]=bus [1]=crc16(name) [2]=vendor [3]=0 [4]=product [5]=0 [6]=version [7]=0
# the 32-hex GUID string is the straight dump of those bytes (see
# SDL_JoystickGetGUIDString). Must match SDL's own GUID for the device.
build_map() {
	name="$1"
	is_gpad="$2"
	read -r bus vendor product version <<EOF
$(device_ids "$name")
EOF
	guid="$(printf '%02x%02x%s%02x%02x0000%02x%02x0000%02x%02x0000' \
		$(((bus & 0xff))) $(((bus >> 8) & 0xff)) \
		"$(crc16_le "$name")" \
		$(((vendor & 0xff))) $(((vendor >> 8) & 0xff)) \
		$(((product & 0xff))) $(((product >> 8) & 0xff)) \
		$(((version & 0xff))) $(((version >> 8) & 0xff)))"

	if [ "$is_gpad" = "1" ]; then
		fields="b:$(btn_idx key_b),a:$(btn_idx key_a),y:$(btn_idx key_y),x:$(btn_idx key_x)"
		fields="${fields},back:$(btn_idx key_select),start:$(btn_idx key_start),guide:$(btn_idx key_menu)"
		fields="${fields},dpleft:$(btn_idx key_left),dpdown:$(btn_idx key_down),dpright:$(btn_idx key_right),dpup:$(btn_idx key_up)"
		fields="${fields},leftshoulder:$(btn_idx key_l1),rightshoulder:$(btn_idx key_r1)"
		fields="${fields},lefttrigger:$(btn_idx key_l2),righttrigger:$(btn_idx key_r2)"
		fields="${fields},leftstick:$(btn_idx key_l3),rightstick:$(btn_idx key_r3)"
	else
		fields="leftx:a0,lefty:a1,rightx:a2,righty:a3"
	fi
	printf '%s,%s,%s,platform:Linux\n' "$guid" "$name" "$fields"
}

gen_board() {
	model=$(trait device_model)
	wifi=$(trait wifi_interface)
	bt=$(trait bluetooth_interface)
	lid=$(trait input_lid_device_name)
	hdmi=$(trait gpu_hdmi_connector)
	rumble=$(trait input_rumble_device_name)
	touch=$(trait input_touch)
	lx=$(trait input_axis_lx)
	rx=$(trait input_axis_rx)
	stick=0
	if has "$lx"; then
		stick=2
		[ "$rx" = "na" ] && stick=1
	fi

	has "$model" && mkfile_force board name "$model"
	mkfile_force board network "$(has "$wifi" && echo 1 || echo 0)"
	mkfile_force board bluetooth "$(has "$bt" && echo 1 || echo 0)"
	mkfile_force board portmaster 0
	mkfile_force board lid "$(has "$lid" && echo 1 || echo 0)"
	mkfile_force board hdmi "$(has "$hdmi" && echo 1 || echo 0)"
	mkfile_force board event 0
	mkfile_force board debugfs 0
	mkfile_force board stick "$stick"
	mkfile_force board touch "$(is1 "$touch" && echo 1 || echo 0)"
	mkfile_force board rgb 0
	has "$rumble" && mkfile_force board rumble "$rumble"
	gpad=$(trait input_gamepad_device_name)
	has "$gpad" && mkfile_force board sdl_map "$(build_map "$gpad" 1)"
}

gen_audio() {
	mkfile_force audio min 0
	mkfile_force audio max 100
}

gen_mux() {
	w=$(trait screen_width)
	h=$(trait screen_height)
	has "$w" && mkfile_force mux width "$w"
	has "$h" && mkfile_force mux height "$h"
}

gen_storage() {
	sd=$(trait storage_sd_node)
	if has "$sd"; then
		for slot in boot rom; do
			mkfile_force storage/${slot} num 1
			mkfile_force storage/${slot} dev "${sd}p1"
			mkfile_force storage/${slot} mount /mnt/sdcard
			mkfile_force storage/${slot} type vfat
			mkfile_force storage/${slot} label minime
		done
	fi
	mkfile_force storage/root mount /
	mkfile_force storage/root type erofs
	mkfile_force storage/root label system
}

gen_cpu() {
	gov=$(trait cpu_governor_path)
	clk=$(trait cpu_clock_path)
	if has "$gov"; then
		mkfile_force cpu governor "$gov"
		mkfile_force cpu default "$(cat "$gov" 2>/dev/null || true)"
		avail=$(cat "${gov%/*}/scaling_available_governors" 2>/dev/null || true)
		has "$avail" && mkfile_force cpu available "$avail"
	fi
	if has "$clk"; then
		mkfile_force cpu scaler "${clk%/*}/scaling_cur_freq"
	fi
}

gen_network() {
	wifi=$(trait wifi_interface)
	has "$wifi" && mkfile_force network iface "$wifi"
}

gen_screen() {
	w=$(trait screen_width)
	h=$(trait screen_height)
	rot=$(trait screen_rotation)
	bmax=$(trait screen_backlight_max)
	hdmi=$(trait gpu_hdmi_connector)
	has "$bmax" && mkfile_force screen bright "$bmax"
	mkfile_force screen wait 0
	mkfile_force screen device /dev/fb0
	has "$hdmi" && mkfile_force screen hdmi "$hdmi"
	if [ "$rot" = "90" ] || [ "$rot" = "270" ]; then
		sw="$h"
		sh="$w"
	else
		sw="$w"
		sh="$h"
	fi
	has "$sw" && mkfile_force screen width "$sw"
	has "$sh" && mkfile_force screen height "$sh"
	has "$rot" && mkfile_force screen rotate "$rot"
}

gen_sdl() {
	rot=$(trait screen_rotation)
	mkfile_force sdl scaler 1
	has "$rot" && mkfile_force sdl rotate "$((rot / 90))"
}

gen_battery() {
	b=$(trait power_battery_sysfs)
	c=$(trait power_charger_online_path)
	if has "$b"; then
		mkfile_force battery capacity "${b}/capacity"
		mkfile_force battery health "${b}/health"
		mkfile_force battery voltage "${b}/voltage_now"
	fi
	has "$c" && mkfile_force battery charger "$c"
}

# The stick axes live on a second evdev device (adc-joystick). SDL maps one
# controller per GUID, so the stick mapping is registered through the same
# gamecontrollerdb files MuOS already loads (retro by default, modern when
# the user switches the remap layout).
seed_stick_map() {
	gpad=$(trait input_gamepad_device_name)
	stick=$(trait input_stick_device_name)
	[ -n "$stick" ] && [ "$stick" != "na" ] && [ "$stick" != "$gpad" ] || return 0
	map=$(build_map "$stick" 0)
	for db in \
		"${MUOS_ROOT}/share/info/gamecontrollerdb/retro.txt" \
		"${MUOS_ROOT}/share/info/gamecontrollerdb/modern.txt"; do
		[ -d "${db%/*}" ] || mkdir -p "${db%/*}"
		if [ -f "$db" ]; then
			grep -Fqx "$map" "$db" || printf '%s\n' "$map" >>"$db"
		else
			printf '%s\n' "$map" >"$db"
		fi
	done
}

# Seed first-run settings: MuOS's default config/settings/general/orientation is
# 2 (= New User Guide, shipped in the payload or compiled-in). Decline it on
# first run; leave any user-chosen value (0/1) untouched.
seed_settings() {
	g="${MUOS_ROOT}/config/settings/general"
	[ -d "$g" ] || mkdir -p "$g"
	if [ ! -f "$g/orientation" ] || [ "$(cat "$g/orientation" 2>/dev/null || true)" = "2" ]; then
		printf '0\n' >"$g/orientation"
	fi
}

gen_board
gen_audio
gen_mux
gen_storage
gen_cpu
gen_network
gen_screen
gen_sdl
gen_battery
seed_stick_map
seed_settings

# Start companion daemons if available.
if [ -x "${MUOS_ROOT}/bin/muhotkey" ] && ! pgrep muhotkey >/dev/null; then
	"${MUOS_ROOT}/bin/muhotkey" &
fi
if [ -x "${MUOS_ROOT}/bin/mubattery" ] && ! pgrep mubattery >/dev/null; then
	"${MUOS_ROOT}/bin/mubattery" &
fi

# Main frontend lifecycle loop: this script is the parent muxfrontend's
# PDEATHSIG relies on, so it must not exit while the frontend runs.
while true; do
	"${MUOS_ROOT}/bin/muxfrontend" || true

	if [ -f /tmp/muos/act_load ]; then
		ACT=$(cat /tmp/muos/act_load)
		rm -f /tmp/muos/act_load
		case "$ACT" in
		shutdown) poweroff && break ;;
		reboot) reboot && break ;;
		esac
	fi

	sleep 0.5
done
