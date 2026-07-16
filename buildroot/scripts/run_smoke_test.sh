#!/bin/bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <board> <kernel_image> <initramfs> <compressed_img>" >&2
    exit 1
fi

BOARD="$1"
KERNEL_IMAGE="$2"
INITRAMFS="$3"
COMPRESSED_IMG="$4"

IMG_NAME="minime-smoke-test-${BOARD}.img"
LOG_FILE="qemu_smoke_test_${BOARD}.log"

echo "=== Starting Smoke Test for ${BOARD} ==="

# Decompress image
echo "Decompressing firmware image..."
gunzip -c "${COMPRESSED_IMG}" > "${IMG_NAME}"

# Ensure QEMU is installed
if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    echo "Installing qemu-system-aarch64..."
    sudo apt-get update -q
    sudo apt-get install -y -q qemu-system-arm
fi

echo "Running QEMU system emulation..."
# Start QEMU in the background. Redirect serial console output to a log file.
# Note: we use -drive if=virtio to use the VirtIO block device which matches our vd*1 search pattern.
qemu-system-aarch64 \
    -machine virt \
    -cpu cortex-a53 \
    -m 1G \
    -nographic \
    -kernel "${KERNEL_IMAGE}" \
    -initrd "${INITRAMFS}" \
    -drive file="${IMG_NAME}",format=raw,if=virtio \
    -append "console=ttyAMA0 root=/dev/ram0 minime_smoke_test=1" \
    -serial file:"${LOG_FILE}" &
QEMU_PID=$!

echo "QEMU started with PID ${QEMU_PID}. Waiting for results..."

# Monitor the log file for success/failure or timeout
PASSED=0
TIMEOUT=90 # seconds
ELAPSED=0

while [ "${ELAPSED}" -lt "${TIMEOUT}" ]; do
    if [ -f "${LOG_FILE}" ]; then
        if grep -q "=== SMOKE TEST: PASSED ===" "${LOG_FILE}"; then
            echo "Smoke test passed!"
            PASSED=1
            break
        elif grep -q "=== SMOKE TEST: FAILED" "${LOG_FILE}"; then
            echo "Smoke test failed!"
            grep "=== SMOKE TEST: FAILED" "${LOG_FILE}"
            break
        fi
    fi
    # Check if QEMU exited early
    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
        echo "QEMU process exited unexpectedly."
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Clean up QEMU process
if kill -0 "${QEMU_PID}" 2>/dev/null; then
    echo "Terminating QEMU..."
    kill "${QEMU_PID}" || true
    sleep 2
    kill -9 "${QEMU_PID}" 2>/dev/null || true
fi

# Print full log for debugging
if [ -f "${LOG_FILE}" ]; then
    echo "=== QEMU Boot Console Log ==="
    cat "${LOG_FILE}"
    echo "============================="
    rm -f "${LOG_FILE}"
fi

# Clean up temp image
rm -f "${IMG_NAME}"

if [ "${PASSED}" -eq 1 ]; then
    echo "=== SMOKE TEST SUCCESSFUL ==="
    exit 0
else
    echo "=== SMOKE TEST FAILED ==="
    exit 1
fi
