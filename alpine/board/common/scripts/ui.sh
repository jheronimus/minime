#!/bin/sh
# shellcheck shell=sh
# ui.sh: launch the configured Minime frontend (MinUI/Allium).
# Called by both the Alpine OpenRC 'ui' service and the Buildroot S60ui wrapper.
# Interface: ui.sh {start|stop|restart|reload}

set -eu

UI_BIN="/mnt/sdcard/.system/minime/bin/minui"
DAEMON=ui

start() {
	echo "Starting UI ($DAEMON)..."

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
	rm -f "$SDCARD_PATH/.minime/gpu_fail"
	rm -f /tmp/next

	# UI lifecycle loop runs in the background so boot can finish
	(
		while true; do
			if [ -f /tmp/poweroff ]; then
				rm -f /tmp/poweroff
				poweroff
				exit 0
			fi

			if [ -x "$UI_BIN" ]; then
				"$UI_BIN" </dev/console >/tmp/ui.log 2>&1
			else
				echo "Missing UI binary: $UI_BIN" >/tmp/ui.log
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
	echo "Stopping UI ($DAEMON)..."
	if [ -f /tmp/watch_jack.pid ]; then
		kill "$(cat /tmp/watch_jack.pid)" 2>/dev/null || true
		rm -f /tmp/watch_jack.pid
	fi
	if [ -f /tmp/ui_loop.pid ]; then
		kill "$(cat /tmp/ui_loop.pid)" 2>/dev/null || true
		rm -f /tmp/ui_loop.pid
	fi
	killall minui minarch keymon clock minput syncsettings say \
		2>/dev/null || true
	sleep 0.5
	killall -9 minui minarch keymon clock minput syncsettings say \
		2>/dev/null || true
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
