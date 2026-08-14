#!/bin/sh
# Retrieve a live screenshot from the target device over network without writing to device storage
# Usage: ./scripts/remote-screenshot.sh [output_file.png] [ip]

set -eu

OUT_PATH="${1:-screenshot.png}"
IP="${2:-}"

if [ -z "$IP" ]; then
    if [ -f "deploy.cfg" ]; then
        IP=$(grep -E '^\s*target_ip=' deploy.cfg | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
    fi
fi

if [ -z "$IP" ]; then
    echo "ERROR: No target IP address specified and target_ip not found in deploy.cfg." >&2
    exit 1
fi

python3 - "$IP" "$OUT_PATH" <<'PYEOF'
import socket, sys, time, base64

ip = sys.argv[1]
out_path = sys.argv[2]

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(15)
try:
    s.connect((ip, 23))
except Exception as e:
    sys.stderr.write(f"ERROR: Failed to connect to {ip}:23 (telnet): {e}\n")
    sys.exit(1)

# Wait for initial telnet banner/prompt
time.sleep(0.3)
try:
    s.recv(4096)
except Exception:
    pass

# Execute remote screenshot with base64 encoding
cmd = b"remote screenshot --base64\n"
s.sendall(cmd)

data_chunks = []
start_time = time.time()
while True:
    try:
        chunk = s.recv(65536)
        if not chunk:
            break
        data_chunks.append(chunk)
        if b"\n" in chunk and time.time() - start_time > 0.5:
            # Check if we have received a full base64 payload and trailing prompt
            combined = b"".join(data_chunks)
            if combined.count(b"\n") >= 2:
                # Give a small margin for remaining bytes
                time.sleep(0.2)
                try:
                    extra = s.recv(65536)
                    if extra:
                        data_chunks.append(extra)
                except Exception:
                    pass
                break
    except socket.timeout:
        break

s.close()

raw_output = b"".join(data_chunks).decode("ascii", errors="ignore")
lines = [l.strip() for l in raw_output.splitlines() if l.strip()]

b64_lines = []
for l in lines:
    if l.startswith("remote screenshot") or l.startswith("#") or l.startswith("/"):
        continue
    # Filter out telnet prompt strings like "~ #" or "minime:/#"
    if l.endswith("#") or l.endswith("$") or l.endswith(">"):
        continue
    # Valid base64 chars only
    clean = "".join(c for c in l if c.isalnum() or c in "+/=")
    if len(clean) > 32:
        b64_lines.append(clean)

if not b64_lines:
    sys.stderr.write("ERROR: No valid base64 image data received from device.\n")
    sys.stderr.write(f"Device output was:\n{raw_output[:500]}\n")
    sys.exit(1)

b64_data = "".join(b64_lines)

try:
    png_bytes = base64.b64decode(b64_data)
except Exception as e:
    sys.stderr.write(f"ERROR: Failed to decode base64 screenshot data: {e}\n")
    sys.exit(1)

if len(png_bytes) < 8 or png_bytes[:8] != b"\x89PNG\r\n\x1a\n":
    sys.stderr.write("ERROR: Captured stream is not a valid PNG image.\n")
    sys.exit(1)

with open(out_path, "wb") as f:
    f.write(png_bytes)

print(f"Screenshot successfully captured: {out_path} ({len(png_bytes)} bytes)")
PYEOF
