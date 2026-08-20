#!/bin/sh
# shellcheck shell=sh
# audio.sh: ALSA audio ownership (single source of truth for .asoundrc).
# The firmware owns ALSA routing; the UI delegates here instead of writing
# .asoundrc itself.
# Subcommands:
#   init         write boot-time .asoundrc from traits (card default)
#   bt-off       restore the boot-time .asoundrc (same as init)
#   bt-on <addr> route .asoundrc to a connected Bluetooth (bluealsa) device

set -eu

TRAITS_FILE="/mnt/sdcard/.minime/traits"
ASOUNDRC_FILE="/mnt/sdcard/.asoundrc"
RUN_ASOUNDRC="/run/asoundrc"

get_trait() {
	key="$1"
	[ -f "$TRAITS_FILE" ] || return 0
	grep "^${key}=" "$TRAITS_FILE" | cut -d= -f2 | tr -d '\r' || true
}

write_card_default() {
	audio_card=$(get_trait audio_card)
	rm -f "$RUN_ASOUNDRC" 2>/dev/null || true
	# "na" and "default" both mean: leave ALSA to its own default routing.
	if [ -n "$audio_card" ] && [ "$audio_card" != "default" ] && [ "$audio_card" != "na" ]; then
		printf 'pcm.!default {\n    type hw\n    card %s\n}\nctl.!default {\n    type hw\n    card %s\n}\n' \
			"$audio_card" "$audio_card" >"$ASOUNDRC_FILE"
	else
		rm -f "$ASOUNDRC_FILE"
	fi
}

usage() {
	echo "Usage: ${0##*/} {init|bt-off|bt-on <addr>}" >&2
	exit 1
}

case "${1:-}" in
init | bt-off)
	# Idempotent: only rewrite when a Bluetooth route is active (either
	# the live /run route or the SD-card .asoundrc a reboot would restore).
	if grep -q "type bluealsa" "$RUN_ASOUNDRC" 2>/dev/null ||
		grep -q "type bluealsa" "$ASOUNDRC_FILE" 2>/dev/null; then
		write_card_default
	fi
	;;
bt-on)
	[ $# -ge 2 ] || usage
	addr="$2"
	# Idempotent: don't rewrite when already routed to this device (the
	# audio monitor re-asserts the route periodically; rewriting an
	# unchanged file would force the UI to reopen audio every cycle).
	if grep -q "device \"$addr\"" "$RUN_ASOUNDRC" 2>/dev/null; then
		exit 0
	fi
	# A2DP always negotiates 48 kHz SBC. The inner `rate 48000` makes the
	# plug layer resample (e.g. 44.1 kHz games) instead of asking BlueALSA
	# to renegotiate the stream, which BlueZ refuses while the transport is
	# settling and tears the A2DP PCM down (silent games).
	content=$(printf 'defaults.bluealsa.device "%s"\ndefaults.bluealsa.profile "a2dp"\npcm.!default {\n    type plug\n    slave {\n        pcm {\n            type bluealsa\n            device "%s"\n            profile "a2dp"\n        }\n        rate 48000\n    }\n}\nctl.!default {\n    type bluealsa\n}\n' \
		"$addr" "$addr")
	printf '%s' "$content" >"$ASOUNDRC_FILE"
	printf '%s' "$content" >"$RUN_ASOUNDRC"
	;;
*)
	usage
	;;
esac
