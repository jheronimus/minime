#!/bin/sh
# shellcheck shell=sh
# audio-monitor.sh: watches D-Bus for Bluetooth audio device connect/disconnect
# and automatically manages /run/asoundrc routing in real-time.

set -u

# On startup, check if any audio device is currently connected
connected_sink=$(bluetoothctl devices Connected 2>/dev/null | head -n 1 | awk '{print $2}')
if [ -n "$connected_sink" ]; then
	/usr/share/minime/scripts/audio.sh bt-on "$connected_sink"
fi

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
					/usr/share/minime/scripts/audio.sh bt-on "$dev_mac"
				fi
			fi
		elif echo "$var_line" | grep -q "boolean false"; then
			/usr/share/minime/scripts/audio.sh bt-off
		fi
		;;
	esac
done
