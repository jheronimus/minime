#!/bin/sh
# Copy a local file to the target device over SSH (dropbear, blank-password
# root). Uses `ssh 'cat >' <file>` because dropbear ships no scp/sftp server.
# Unlike FTP uploads (root = /mnt/sdcard), this can write any path as root.
# Usage: ./scripts/scp-upload.sh <local_file> <remote_path> [ip]

set -eu

LOCAL_FILE="${1:-}"
REMOTE_PATH="${2:-}"
IP="${3:-}"

if [ -z "$LOCAL_FILE" ] || [ -z "$REMOTE_PATH" ]; then
	echo "Usage: $0 <local_file> <remote_path> [ip]" >&2
	exit 1
fi

if [ ! -f "$LOCAL_FILE" ]; then
	echo "ERROR: Local file '$LOCAL_FILE' not found." >&2
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

# A relative remote path defaults to the SD card root, matching the old FTP
# behavior (`just upload file.sh` -> /mnt/sdcard/file.sh); absolute paths go
# anywhere as root.
case "$REMOTE_PATH" in
/*) ;;
*) REMOTE_PATH="/mnt/sdcard/$REMOTE_PATH" ;;
esac

echo "Uploading '$LOCAL_FILE' -> root@$IP:$REMOTE_PATH ..."

exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	-o ConnectTimeout=5 -o LogLevel=ERROR \
	root@"$IP" "cat > '$REMOTE_PATH'" <"$LOCAL_FILE"
