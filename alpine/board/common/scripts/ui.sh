#!/bin/sh
# shellcheck shell=sh
# ui.sh: launch the installed Minime frontend.
# Called by both the Alpine OpenRC 'ui' service and the Buildroot S60ui wrapper.
# Interface: ui.sh {start|stop|restart|reload}
#
# Each UI ships its own filesystem layout and boot script.
# Minime only provides the hardware glue and lifecycle loop.

set -eu

# UI detection: prefer MinUI, fall back to Allium.
if [ -x "/mnt/sdcard/.system/minime/bin/minui" ]; then
	UI_BIN="/mnt/sdcard/.system/minime/bin/minui"
	UI_NAME="MinUI"
elif [ -x "/mnt/sdcard/.ui/bin/alliumd" ]; then
	UI_BIN="/mnt/sdcard/.ui/bin/alliumd"
	UI_NAME="Allium"
else
	UI_BIN=""
	UI_NAME="unknown"
fi

start() {
	echo "Starting UI (${UI_NAME})..."

	# Headphone jack routing daemon for rk817ext sound card
	if amixer -c rk817ext controls >/dev/null 2>&1; then
		(
			while true; do
				if amixer -c rk817ext cget numid=1 2>/dev/null | grep -q "values=on"; then
					target_state="HP"
					current_val="0"
				else
					target_state="SPK"
					current_val="1"
				fi
				if ! amixer -c rk817ext cget name='Playback Mux' 2>/dev/null | grep -q "values=$current_val"; then
					amixer -c rk817ext sset 'Playback Mux' "$target_state" >/dev/null 2>&1
				fi
				sleep 2
			done
		) &
		echo $! >/tmp/watch_jack.pid
	fi

	export HOME=/mnt/sdcard

	# Set up dynamic .asoundrc based on traits sound_card
	TRAITS_FILE="/mnt/sdcard/.minime/traits"
	ASOUNDRC_FILE="/mnt/sdcard/.asoundrc"
	if [ -f "$TRAITS_FILE" ]; then
		sound_card=$(grep "^sound_card=" "$TRAITS_FILE" | cut -d= -f2 | tr -d '\r')
		if [ -n "$sound_card" ] && [ "$sound_card" != "default" ]; then
			printf "pcm.!default {\n    type hw\n    card %s\n}\nctl.!default {\n    type hw\n    card %s\n}\n" \
				"$sound_card" "$sound_card" >"$ASOUNDRC_FILE"
		else
			rm -f "$ASOUNDRC_FILE"
		fi
	fi

	# Ensure backlight is visible until userspace takes over
	for bl in /sys/class/backlight/*/brightness; do
		[ -w "$bl" ] && echo 5 >"$bl" 2>/dev/null || true
	done

	# Clear GPU failure boot-loop sentinel and stale next commands
	rm -f /mnt/sdcard/.minime/gpu_fail
	rm -f /tmp/next

	# UI lifecycle loop runs in the background so boot can finish
	(
		while true; do
			if [ -f /tmp/poweroff ]; then
				rm -f /tmp/poweroff
				poweroff
				exit 0
			fi

			if [ -n "${UI_BIN:-}" ] && [ -x "$UI_BIN" ]; then
				if [ -d /mnt/sdcard ]; then
					printf '[UI %s] Executing %s (%s)\n' \
						"$(date -u +'%T' 2>/dev/null || true)" "$UI_NAME" "$UI_BIN" >> /mnt/sdcard/boot.log 2>/dev/null || true
					sync 2>/dev/null || true
				fi
				"$UI_BIN" </dev/console >/tmp/ui.log 2>&1
				[ -d /mnt/sdcard ] && cp -f /tmp/ui.log /mnt/sdcard/ui.log 2>/dev/null || true
			else
				echo "No UI binary found" >/tmp/ui.log
				if [ -d /mnt/sdcard ]; then
					printf '[UI %s] ERROR: No UI binary found\n' \
						"$(date -u +'%T' 2>/dev/null || true)" >> /mnt/sdcard/boot.log 2>/dev/null || true
					cp -f /tmp/ui.log /mnt/sdcard/ui.log 2>/dev/null || true
					sync 2>/dev/null || true
				fi
				sleep 5
				continue
			fi

			if [ -f /tmp/next ]; then
				CMD=$(cat /tmp/next)
				rm -f /tmp/next
				eval "$CMD" </dev/console >/dev/console 2>&1
			else
				sleep 3600
				exit 0
			fi
		done
	) &
	echo $! >/tmp/ui_loop.pid
}

stop() {
	echo "Stopping UI (${UI_NAME})..."
	if [ -f /tmp/watch_jack.pid ]; then
		kill "$(cat /tmp/watch_jack.pid)" 2>/dev/null || true
		rm -f /tmp/watch_jack.pid
	fi
	if [ -f /tmp/ui_loop.pid ]; then
		kill "$(cat /tmp/ui_loop.pid)" 2>/dev/null || true
		rm -f /tmp/ui_loop.pid
	fi
	# Best-effort cleanup of known UI processes.
	# Each UI should handle its own children; these are belt-and-suspenders.
	killall minui minarch keymon clock minput syncsettings say \
		alliumd allium-launcher allium-menu 2>/dev/null || true
	sleep 0.5
	killall -9 minui minarch keymon clock minput syncsettings say \
		alliumd allium-launcher allium-menu 2>/dev/null || true
}

case "${1:-}" in
start) start ;;
stop) stop ;;
restart | reload)
	stop
	sleep 1
	start
	;;
*)
	echo "Usage: $0 {start|stop|restart|reload}" >&2
	exit 1
	;;
esac
