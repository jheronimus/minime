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

get_trait() {
	key="$1"
	[ -f "$TRAITS_FILE" ] || return 0
	grep "^${key}=" "$TRAITS_FILE" | cut -d= -f2 | tr -d '\r' || true
}

write_card_default() {
	audio_card=$(get_trait audio_card)
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
	write_card_default
	;;
bt-on)
	[ $# -ge 2 ] || usage
	addr="$2"
	printf 'defaults.bluealsa.device "%s"\ndefaults.bluealsa.profile "a2dp"\npcm.!default {\n    type plug\n    slave.pcm {\n        type bluealsa\n        device "%s"\n        profile "a2dp"\n    }\n}\nctl.!default {\n    type bluealsa\n}\n' \
		"$addr" "$addr" >"$ASOUNDRC_FILE"
	;;
*)
	usage
	;;
esac
