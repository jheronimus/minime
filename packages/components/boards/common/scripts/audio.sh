#!/bin/sh
# shellcheck shell=sh
# audio.sh: ALSA audio ownership (single source of truth for .asoundrc).
# The firmware owns ALSA routing; the UI delegates here instead of writing
# .asoundrc itself.
#
# Routing model: the game's default PCM is re-pointed by writing /run/asoundrc.
# The running emulator's SND layer (workspace/all/common/api.c) notices the
# mtime change and re-opens SDL audio against the new default within ~1s.
#
# Subcommands:
#   init         clear any stale dynamic .asoundrc
#   bt-off       restore hardware routing (same as init)
#   bt-on <addr> route .asoundrc to a connected Bluetooth (bluealsa) device
#   jack-in      headphone inserted: mute internal speakers
#   jack-out     headphone removed: unmute internal speakers

set -eu

ASOUNDRC_FILE="/mnt/sdcard/.asoundrc"
RUN_ASOUNDRC="/run/asoundrc"
TRAITS_FILE="/mnt/sdcard/.minime/traits"

get_trait() {
	key="$1"
	[ -f "$TRAITS_FILE" ] || return 0
	grep "^${key}=" "$TRAITS_FILE" 2>/dev/null | cut -d= -f2 | tr -d '\r' || true
}

set_speaker_gating() {
	state="$1" # "off" or "on"
	audio_card=$(get_trait audio_card)
	card_args=""
	if [ -n "$audio_card" ] && [ "$audio_card" != "default" ]; then
		card_args="-c $audio_card"
	fi

	if [ "$state" = "off" ]; then
		# Mute/disable internal speaker and external speaker amp
		amixer -q $card_args sset 'Internal Speakers' off 2>/dev/null || true
		amixer -q $card_args sset 'Internal Speakers' mute 2>/dev/null || true
		amixer -q $card_args sset 'Speaker' mute 2>/dev/null || true
		amixer -q $card_args sset 'Speaker Amp' mute 2>/dev/null || true
		amixer -q $card_args sset 'Playback Path' HP_NO_MIC 2>/dev/null || true
	else
		# Unmute/enable internal speaker and external speaker amp
		amixer -q $card_args sset 'Internal Speakers' on 2>/dev/null || true
		amixer -q $card_args sset 'Internal Speakers' unmute 2>/dev/null || true
		amixer -q $card_args sset 'Speaker' unmute 2>/dev/null || true
		amixer -q $card_args sset 'Speaker Amp' unmute 2>/dev/null || true
		amixer -q $card_args sset 'Playback Path' SPK 2>/dev/null || true
	fi
}

usage() {
	echo "Usage: ${0##*/} {init|bt-off|bt-on <addr>|jack-in|jack-out}" >&2
	exit 1
}

case "${1:-}" in
init | bt-off)
	rm -f "$RUN_ASOUNDRC" "$ASOUNDRC_FILE" 2>/dev/null || true
	;;
bt-on)
	[ $# -ge 2 ] || usage
	addr="$2"
	# Idempotent: don't rewrite when already routed to this device.
	if grep -q "device \"$addr\"" "$RUN_ASOUNDRC" 2>/dev/null; then
		exit 0
	fi
	# A2DP always negotiates 48 kHz SBC. The plug layer resamples the game's
	# native rate (e.g. 44.1 kHz) to 48 kHz instead of asking BlueALSA to
	# renegotiate.
	content=$(printf 'defaults.bluealsa.device "%s"\ndefaults.bluealsa.profile "a2dp"\npcm.!default {\n    type plug\n    slave {\n        pcm {\n            type bluealsa\n            device "%s"\n            profile "a2dp"\n        }\n        rate 48000\n    }\n}\nctl.!default {\n    type bluealsa\n}\n' \
		"$addr" "$addr")
	printf '%s' "$content" >"$RUN_ASOUNDRC"
	;;
jack-in)
	set_speaker_gating off
	;;
jack-out)
	set_speaker_gating on
	;;
*)
	usage
	;;
esac
