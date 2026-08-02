#!/usr/bin/env bash
# Execute a remote shell command on target device over telnet
# Usage: ./scripts/remote-cmd.sh <command> [ip]

set -euo pipefail

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
out = s.recv(65536).decode(errors="ignore")
s.close()

lines = out.splitlines()
if lines and (lines[0].strip() == cmd or cmd in lines[0]):
    lines = lines[1:]
print("\n".join(lines).strip())
EOF
