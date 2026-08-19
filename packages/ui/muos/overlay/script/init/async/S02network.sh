#!/bin/sh
set -eu

ACTION="${1:-connect}"
PROFILE="${2:-}"

IFACE="wlan0"
CFG_DIR="/mnt/sdcard/.muos/config/network"
MUOS_NET_DIR="/mnt/sdcard/MUOS/network"

case "$ACTION" in
	connect)
		SSID=""
		PASS=""

		# Check profile ini if specified
		if [ -n "$PROFILE" ] && [ -f "${MUOS_NET_DIR}/${PROFILE}.ini" ]; then
			SSID=$(grep -E '^\s*ssid\s*=' "${MUOS_NET_DIR}/${PROFILE}.ini" | head -1 | cut -d= -f2- | tr -d ' "\r')
			PASS=$(grep -E '^\s*pass\s*=' "${MUOS_NET_DIR}/${PROFILE}.ini" | head -1 | cut -d= -f2- | tr -d ' "\r')
		fi

		# Fallback to single-file config if not in profile
		if [ -z "$SSID" ] && [ -f "${CFG_DIR}/ssid" ]; then
			SSID=$(cat "${CFG_DIR}/ssid" 2>/dev/null | tr -d '\r\n')
		fi
		if [ -z "$PASS" ] && [ -f "${CFG_DIR}/pass" ]; then
			PASS=$(cat "${CFG_DIR}/pass" 2>/dev/null | tr -d '\r\n')
		fi

		[ -n "$SSID" ] || exit 0

		# Connect via iwd / iwctl
		if command -v iwctl >/dev/null 2>&1; then
			if [ -n "$PASS" ]; then
				iwctl --passphrase "$PASS" station "$IFACE" connect "$SSID" || true
			else
				iwctl station "$IFACE" connect "$SSID" || true
			fi
		fi

		# Persist to Minime's wifi.cfg for seamless cross-UI auto-connect
		mkdir -p /mnt/sdcard/.minime/config
		cat << WIFICFG > /mnt/sdcard/.minime/config/wifi.cfg
SSID="$SSID"
PASS="$PASS"
WIFICFG
		cp -f /mnt/sdcard/.minime/config/wifi.cfg /mnt/sdcard/wifi.cfg 2>/dev/null || true
		;;

	stop|disconnect)
		if command -v iwctl >/dev/null 2>&1; then
			iwctl station "$IFACE" disconnect || true
		fi
		;;

	*)
		exit 0
		;;
esac
