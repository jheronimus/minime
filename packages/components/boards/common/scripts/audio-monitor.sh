#!/bin/sh
# shellcheck shell=sh
# audio-monitor.sh: keeps ALSA routed to the connected Bluetooth audio
# device. Reacts to D-Bus connect/disconnect events and re-asserts the
# route every few seconds to self-heal against anything that resets
# /run/asoundrc after this daemon starts (e.g. the UI init step, which
# runs later in the boot order). audio.sh is idempotent, so re-asserting
# an unchanged route is a no-op.

set -u

AUDIO_SCRIPT="/usr/share/minime/scripts/audio.sh"
MIRROR_TARGET="/run/bt-audio-target"

set_target() {
	printf '%s\n' "$1" >"$MIRROR_TARGET"
}

recheck() {
	connected_sink=""
	for dev in $(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'); do
		if bluetoothctl info "$dev" 2>/dev/null | grep -q "Audio Sink"; then
			connected_sink="$dev"
			break
		fi
	done
	if [ -n "$connected_sink" ]; then
		"$AUDIO_SCRIPT" bt-on "$connected_sink"
		set_target "$connected_sink"
	else
		set_target ""
		"$AUDIO_SCRIPT" bt-off
	fi
}

# Keep the FIFO open for the lifetime of the system. The helper drains the
# mirrored stream when Bluetooth is absent and feeds BlueALSA when present.
if [ -x /usr/bin/bt-mirror ]; then
	start-stop-daemon -S -q -b -m -p /run/bt-mirror.pid -x /usr/bin/bt-mirror
fi

# Re-assert on startup and periodically (idempotent, cheap).
recheck
(while :; do
	sleep 5
	recheck
done) &
loop_pid=$!
trap 'kill "$loop_pid" 2>/dev/null; start-stop-daemon -K -q -p /run/bt-mirror.pid 2>/dev/null || true' EXIT INT TERM

dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" 2>/dev/null | while read -r line; do
	case "$line" in
	*"signal time="*path=/org/bluez/*/dev_*)
		dev_path=$(echo "$line" | sed -n 's/.*path=\([^ ]*\).*/\1/p')
		dev_mac=$(echo "$dev_path" | sed -n 's#.*/dev_\(.*\)#\1#p' | tr '_' ':')
		;;
	*"string \"Connected\""*)
		read -r var_line
		if echo "$var_line" | grep -q "boolean true"; then
			if [ -n "${dev_mac:-}" ]; then
				if bluetoothctl info "$dev_mac" 2>/dev/null | grep -q "Audio Sink"; then
					"$AUDIO_SCRIPT" bt-on "$dev_mac"
					set_target "$dev_mac"
				fi
			fi
		elif echo "$var_line" | grep -q "boolean false"; then
			set_target ""
			"$AUDIO_SCRIPT" bt-off
		fi
		;;
	esac
done

kill "$loop_pid" 2>/dev/null
