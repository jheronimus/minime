#!/bin/sh
# shellcheck shell=sh
# ui.sh: launch the installed Minime frontend.
# Called by both the Alpine OpenRC 'ui' service and the Buildroot S60ui wrapper.
# Interface: ui.sh {start|stop|restart|reload}
#
# Each UI ships its own filesystem layout and boot script.
# Minime only provides the hardware glue and lifecycle loop.

set -eu

TRAITS_FILE="/mnt/sdcard/.minime/traits"
ASOUNDRC_FILE="/mnt/sdcard/.asoundrc"
UI_ENV_FILE="/mnt/sdcard/.minime/ui.env"

get_trait() {
	key="$1"
	[ -f "$TRAITS_FILE" ] || return 0
	grep "^${key}=" "$TRAITS_FILE" | cut -d= -f2 | tr -d '\r' || true
}

read_ui_env() {
	key="$1"
	[ -f "$UI_ENV_FILE" ] || return 0
	grep "^${key}=" "$UI_ENV_FILE" | cut -d= -f2 | tr -d '\r"' || true
}

UI_NAME=$(read_ui_env UI_NAME)
UI_BIN=$(read_ui_env UI_BIN)
UI_PROCESSES=$(read_ui_env UI_PROCESSES)

start() {
	echo "Starting UI (${UI_NAME:-none})..."

	sound_card=$(get_trait sound_card)
	if [ -n "$sound_card" ] && [ "$sound_card" != "default" ]; then
		printf "pcm.!default {\n    type hw\n    card %s\n}\nctl.!default {\n    type hw\n    card %s\n}\n" \
			"$sound_card" "$sound_card" >"$ASOUNDRC_FILE"
	else
		rm -f "$ASOUNDRC_FILE"
	fi

	# Headphone jack routing daemon for sound card
	if [ -n "$sound_card" ] && [ "$sound_card" != "default" ] && amixer -c "$sound_card" controls >/dev/null 2>&1; then
		(
			while true; do
				if amixer -c "$sound_card" cget numid=1 2>/dev/null | grep -q "values=on"; then
					target_state="HP"
					current_val="0"
				else
					target_state="SPK"
					current_val="1"
				fi
				if ! amixer -c "$sound_card" cget name='Playback Mux' 2>/dev/null | grep -q "values=$current_val"; then
					amixer -c "$sound_card" sset 'Playback Mux' "$target_state" >/dev/null 2>&1
				fi
				sleep 2
			done
		) &
		echo $! >/tmp/watch_jack.pid
	fi

	export HOME=/mnt/sdcard

	# Ensure backlight is visible until userspace takes over
	for bl in /sys/class/backlight/*/brightness; do
		[ -w "$bl" ] && echo 5 >"$bl" 2>/dev/null || true
	done

	# Clear GPU failure boot-loop sentinel and stale next commands
	rm -f /mnt/sdcard/.minime/gpu_fail
	rm -f /tmp/next

	if [ -z "$UI_BIN" ] || ! [ -x "$UI_BIN" ]; then
		echo "No UI binary found" >/tmp/ui.log
		if [ -d /mnt/sdcard ]; then
			printf '[UI %s] ERROR: No UI binary found\n' \
				"$(date -u +'%T' 2>/dev/null || true)" >> /mnt/sdcard/boot.log 2>/dev/null || true
			cp -f /tmp/ui.log /mnt/sdcard/ui.log 2>/dev/null || true
			sync 2>/dev/null || true
		fi
		return 0
	fi

	# UI lifecycle loop runs in the background so boot can finish
	(
		while true; do
			if [ -f /tmp/poweroff ]; then
				rm -f /tmp/poweroff
				poweroff
				exit 0
			fi

			if [ -d /mnt/sdcard ]; then
				printf '[UI %s] Executing %s (%s)\n' \
					"$(date -u +'%T' 2>/dev/null || true)" "$UI_NAME" "$UI_BIN" >> /mnt/sdcard/boot.log 2>/dev/null || true
				sync 2>/dev/null || true
			fi
			"$UI_BIN" </dev/console >/tmp/ui.log 2>&1
			[ -d /mnt/sdcard ] && cp -f /tmp/ui.log /mnt/sdcard/ui.log 2>/dev/null || true

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
	echo "Stopping UI (${UI_NAME:-frontend})..."
	if [ -f /tmp/watch_jack.pid ]; then
		kill "$(cat /tmp/watch_jack.pid)" 2>/dev/null || true
		rm -f /tmp/watch_jack.pid
	fi
	if [ -f /tmp/ui_loop.pid ]; then
		loop_pid="$(cat /tmp/ui_loop.pid)"
		pkill -P "$loop_pid" 2>/dev/null || true
		kill "$loop_pid" 2>/dev/null || true
		rm -f /tmp/ui_loop.pid
	fi
	if [ -n "${UI_PROCESSES:-}" ]; then
		# shellcheck disable=SC2086
		killall $UI_PROCESSES 2>/dev/null || true
		sleep 0.5
		# shellcheck disable=SC2086
		killall -9 $UI_PROCESSES 2>/dev/null || true
	fi
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
# Trigger buildroot too
