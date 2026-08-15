#!/bin/sh
# Execute a remote shell command on target device over SSH (dropbear,
# blank-password root login). Prefer this over telnet for reliable sessions.
# Usage: ./scripts/ssh-cmd.sh <command> [ip]

set -eu

CMD="${1:-}"
IP="${2:-}"

if [ -z "$CMD" ]; then
	echo "Usage: $0 <command> [ip]" >&2
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
