#!/bin/sh
# Execute a remote shell command on target device over SSH (dropbear,
# blank-password root login). The command is read from $REMOTE_CMD_FILE (set by
# `just rsh`) so arbitrary shell metacharacters survive; a positional command
# is supported as a fallback.
# Usage: ./scripts/ssh-cmd.sh [ip]   (command read from $REMOTE_CMD_FILE)
#        ./scripts/ssh-cmd.sh <command> [ip]

set -eu

IP="${1:-}"
CMD="${REMOTE_CMD_FILE:-}"

if [ -n "$CMD" ]; then
	CMD="$(cat "$CMD")"
elif [ $# -ge 1 ]; then
	IP="${1:-}"
	CMD="${2:-}"
fi

if [ -z "$CMD" ]; then
	echo "Usage: $0 <command> [ip], or set REMOTE_CMD_FILE" >&2
	exit 1
fi

if [ -z "$IP" ]; then
	if [ -f "deploy.cfg" ]; then
		IP=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
	fi
fi

if [ -z "$IP" ]; then
	echo "ERROR: No target IP address specified and target_ip not found in deploy.cfg." >&2
	exit 1
fi

exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o ConnectTimeout=5 -o LogLevel=ERROR root@"$IP" "$CMD"
