#!/bin/sh
# Execute a remote shell command on target device.
# Defaults to SSH (dropbear, blank-password root). Pass --telnet as the first
# argument to force telnet. The command is read from $REMOTE_CMD_FILE (set by
# `just shell`) so arbitrary shell metacharacters survive; when --telnet is the
# first arg, just shifts the real command into the [ip] slot.
# Usage: ./scripts/remote-cmd.sh [ip]   (command read from $REMOTE_CMD_FILE)

set -eu

IP_ARG="${1:-}"
CMD="$(cat "${REMOTE_CMD_FILE:-}" 2>/dev/null || true)"
MODE="ssh"

if [ -z "$CMD" ] && [ $# -ge 1 ]; then
	if [ "$1" = "--telnet" ]; then
		MODE="telnet"
		CMD="${2:-}"
		IP_ARG="${3:-}"
	else
		CMD="$1"
		IP_ARG="${2:-}"
	fi
fi

IP="$IP_ARG"
if [ "$CMD" = "--telnet" ]; then
	MODE="telnet"
	CMD="$IP_ARG"
	IP=""
elif [ "$IP_ARG" = "--telnet" ]; then
	MODE="telnet"
	IP=""
fi

if [ -z "$CMD" ]; then
	echo "ERROR: REMOTE_CMD_FILE is empty or unset." >&2
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

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"

if [ "$MODE" = "ssh" ]; then
	exec ssh $SSH_OPTS root@"$IP" "$CMD"
fi

# Telnet transport.
python3 - "$IP" "$CMD" <<'EOF'
import socket, sys, time, re

ip = sys.argv[1]
cmd = sys.argv[2]

s = socket.socket()
s.settimeout(10)
s.connect((ip, 23))
time.sleep(0.5)
s.recv(4096)
s.sendall(cmd.encode() + b"\n")
time.sleep(1.5)
out = b""
try:
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        out += chunk
except socket.timeout:
    pass
s.close()

text = out.decode(errors="ignore")
lines = text.splitlines()
def clean_line(l):
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07]*\x07", "", l).strip()
if lines and (clean_line(lines[0]) == cmd or cmd in lines[0]):
    lines = lines[1:]
while lines and (clean_line(lines[-1]).endswith("#") or clean_line(lines[-1]).endswith("$") or clean_line(lines[-1]).endswith(">")):
    lines.pop()
print("\n".join(clean_line(l) for l in lines).strip())
EOF
