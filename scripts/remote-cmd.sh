#!/bin/sh
# Execute a remote shell command on target device.
# Prefers SSH (dropbear, enabled by default) and falls back to telnet for
# devices that haven't updated yet. SSH avoids telnet's fragile pty sessions
# and command mangling.
# Usage: ./scripts/remote-cmd.sh [ip]   (command read from $REMOTE_CMD_FILE)
#        ./scripts/remote-cmd.sh <command> [ip]

set -eu

IP="${1:-}"
CMD="${REMOTE_CMD_FILE:-}"

if [ -n "$CMD" ]; then
	# command arrives in a file so arbitrary shell metacharacters survive
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

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 -o BatchMode=yes -o LogLevel=ERROR"

# Probe SSH availability first so the command runs exactly once.
if command -v ssh >/dev/null 2>&1 && ssh $SSH_OPTS root@"$IP" true 2>/dev/null; then
	exec ssh $SSH_OPTS root@"$IP" "$CMD"
fi

# Fall back to telnet.
python3 - "$IP" "$CMD" <<'EOF'
import socket, sys, time

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
# Drop the echoed command and trailing prompt (including busybox's \x1b[6n)
import re
def clean_line(l):
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07]*\x07", "", l).strip()
if lines and (clean_line(lines[0]) == cmd or cmd in lines[0]):
    lines = lines[1:]
while lines and (clean_line(lines[-1]).endswith("#") or clean_line(lines[-1]).endswith("$") or clean_line(lines[-1]).endswith(">")):
    lines.pop()
print("\n".join(clean_line(l) for l in lines).strip())
EOF
