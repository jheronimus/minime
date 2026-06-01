#!/bin/bash
set -euo pipefail

PHASE="${1:-}"

if [[ "$PHASE" != "export" && "$PHASE" != "import" ]]; then
    echo "Usage: $0 [export|import]"
    exit 1
fi

ORB_MACHINE="builder"
ORB_USER="ilembitov"
TMP_DIR="$(pwd)/tmp_migration"

if [[ "$PHASE" == "export" ]]; then
    echo "=== PHASE 1: Exporting from OrbStack VM ==="
    if ! command -v orb >/dev/null 2>&1; then
        echo "Error: 'orb' command not found." >&2
        exit 1
    fi

    if ! orb list --running --quiet 2>/dev/null | grep -qx "$ORB_MACHINE"; then
        echo "Error: OrbStack VM '$ORB_MACHINE' is not running." >&2
        exit 1
    fi

    mkdir -p "$TMP_DIR"
    echo "1. Exporting .buildroot-ccache..."
    orb -m "$ORB_MACHINE" -u "$ORB_USER" tar -cf - -C /home/"$ORB_USER" .buildroot-ccache | tar -xf - -C "$TMP_DIR/"
    echo "2. Exporting .buildroot-dl..."
    orb -m "$ORB_MACHINE" -u "$ORB_USER" tar -cf - -C /home/"$ORB_USER" .buildroot-dl | tar -xf - -C "$TMP_DIR/"

    echo "=== Export completed successfully! ==="
    echo "Next steps:"
    echo "1. Stop OrbStack VM (e.g., 'orb stop $ORB_MACHINE' or quit OrbStack app)."
    echo "2. Start Colima using:"
    echo "   colima start --cpu 4 --memory 8 --arch aarch64 --vm-type vz --mount-type virtiofs"
    echo "3. Run this script again to import the caches into Docker:"
    echo "   $0 import"

elif [[ "$PHASE" == "import" ]]; then
    echo "=== PHASE 2: Importing to Docker volumes ==="
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: 'docker' command not found. Ensure Colima is started." >&2
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon is not running. Ensure Colima is started." >&2
        exit 1
    fi

    if [ ! -d "$TMP_DIR/.buildroot-ccache" ] || [ ! -d "$TMP_DIR/.buildroot-dl" ]; then
        echo "Error: Exported directories not found in $TMP_DIR. Please run export phase first." >&2
        exit 1
    fi

    echo "1. Creating Docker named volumes..."
    docker volume create minime-buildroot-ccache
    docker volume create minime-buildroot-dl

    echo "2. Importing caches into Docker volumes..."
    docker run --rm \
        -v "$TMP_DIR":/backup \
        -v minime-buildroot-ccache:/ccache \
        -v minime-buildroot-dl:/dl \
        alpine sh -c "
            echo 'Copying ccache...';
            cp -a /backup/.buildroot-ccache/. /ccache/;
            echo 'Copying dl...';
            cp -a /backup/.buildroot-dl/. /dl/;
            echo 'Setting ownership to UID 1000...';
            chown -R 1000:1000 /ccache /dl;
            echo 'Import completed inside container.'
        "

    echo "3. Cleaning up temporary files..."
    rm -rf "$TMP_DIR"

    echo "=== Import completed successfully! ==="
    echo "Your buildroot caches are now securely stored inside Docker named volumes."
fi
