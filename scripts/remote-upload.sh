#!/usr/bin/env bash
# Upload a file to target device over FTP
# Usage: ./scripts/remote-upload.sh <local_file> [remote_filename] [ip]

set -euo pipefail

LOCAL_FILE="${1:-}"
REMOTE_FILE="${2:-}"
IP="${3:-}"

if [ -z "$LOCAL_FILE" ]; then
    echo "Usage: $0 <local_file> [remote_filename] [ip]" >&2
    exit 1
fi

if [ ! -f "$LOCAL_FILE" ]; then
    echo "ERROR: Local file '$LOCAL_FILE' not found." >&2
    exit 1
fi

if [ -z "$REMOTE_FILE" ]; then
    REMOTE_FILE="$(basename "$LOCAL_FILE")"
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

echo "Uploading '$LOCAL_FILE' -> '$REMOTE_FILE' on $IP..."

curl -s -S -u root: -T "$LOCAL_FILE" "ftp://$IP/$REMOTE_FILE"

echo "Upload completed successfully!"
