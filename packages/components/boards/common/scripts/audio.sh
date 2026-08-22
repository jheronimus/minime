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

set -eu

ASOUNDRC_FILE="/mnt/sdcard/.asoundrc"
RUN_ASOUNDRC="/run/asoundrc"

usage() {
	echo "Usage: ${0##*/} {init|bt-off|bt-on <addr>}" >&2
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
*)
	usage
	;;
esac
