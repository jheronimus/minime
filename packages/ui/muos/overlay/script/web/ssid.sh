#!/bin/sh
set -eu

OUT="/tmp/net_scan"
rm -f "$OUT"

IFACE="wlan0"

# Trigger scan
if command -v iwctl >/dev/null 2>&1; then
	iwctl station "$IFACE" scan 2>/dev/null || true
	sleep 1.5
	# Extract network names from iwctl get-networks
	# The output format has network names in the first column after markers (> / *)
	iwctl station "$IFACE" get-networks 2>/dev/null | \
		sed -e 's/\x1b\[[0-9;]*m//g' \
		    -e 's/^[[:space:]]*[>*][[:space:]]*//' \
		    -e 's/^[[:space:]]*//' | \
		grep -v -E '^(Available networks|-+|Network name|Scanning)' | \
		awk '{print $1}' | \
		grep -v '^$' | sort -u > "$OUT" || true
elif command -v iw >/dev/null 2>&1; then
	iw dev "$IFACE" scan 2>/dev/null | \
		grep 'SSID: ' | sed 's/^[[:space:]]*SSID: //' | \
		grep -v '^$' | sort -u > "$OUT" || true
fi

if [ ! -s "$OUT" ]; then
	printf '[!]\n' > "$OUT"
fi
