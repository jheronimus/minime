#!/bin/sh
# Retrieve a live screenshot from the target device over the network without
# writing to device storage. Prefers SSH (dropbear) over telnet, and falls
# back from the DRM plane to the framebuffer when the display is owned by an
# SDL/kmsdrm app.
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

python3 - "$OUT_PATH" "$IP" <<'PYEOF'
import socket, sys, time, base64, subprocess

out_path = sys.argv[1]
ip = sys.argv[2]

SSH_OPTS = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR"]

def parse_png(raw):
    lines = raw.splitlines()
    b64 = []
    for l in lines:
        l = l.strip()
        if not l or l.startswith("remote") or l.startswith("#") or l.startswith("/"):
            continue
        if l.endswith("#") or l.endswith("$") or l.endswith(">"):
            continue
        clean = "".join(c for c in l if c.isalnum() or c in "+/=")
        if len(clean) > 32:
            b64.append(clean)
    if not b64:
        return None
    try:
        data = base64.b64decode("".join(b64))
    except Exception:
        return None
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return data
    return None

def via_ssh(backend):
    cmd = ["remote screenshot", "--backend", backend, "--base64"] if backend else ["remote screenshot", "--base64"]
    proc = subprocess.run(["ssh"] + SSH_OPTS + ["root@" + ip] + [" ".join(cmd)],
                          capture_output=True, timeout=20)
    if proc.returncode != 0:
        return None
    return parse_png(proc.stdout.decode(errors="ignore"))

def via_telnet(backend):
    try:
        s = socket.create_connection((ip, 23), timeout=10)
        s.settimeout(5)
        time.sleep(0.3)
        try:
            s.recv(4096)
        except Exception:
            pass
        cmdline = "remote screenshot --backend %s --base64\n" % backend if backend else "remote screenshot --base64\n"
        s.sendall(cmdline.encode())
        chunks = []
        try:
            while True:
                c = s.recv(65536)
                if not c:
                    break
                chunks.append(c)
        except socket.timeout:
            pass
        s.close()
        return parse_png(b"".join(chunks).decode(errors="ignore"))
    except Exception:
        return None

# DRM first, then FB; SSH first, then telnet.
for kind, chan in (("ssh", via_ssh), ("telnet", via_telnet)):
    for backend in ("drm", "fb"):
        png = chan(backend)
        if png:
            with open(out_path, "wb") as f:
                f.write(png)
            print(f"Screenshot successfully captured: {out_path} ({len(png)} bytes) via {kind}/{backend}")
            sys.exit(0)

sys.stderr.write("ERROR: Failed to capture a screenshot via any channel/backend.\n")
sys.exit(1)
PYEOF
