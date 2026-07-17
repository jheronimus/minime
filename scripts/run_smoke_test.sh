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
TEST_LAUNCH_SH="smoke_test_launch.sh"

echo "=== Starting Smoke Test for ${BOARD} ==="

# 1. Install dependencies
if ! command -v qemu-system-aarch64 >/dev/null 2>&1 || ! command -v mcopy >/dev/null 2>&1 || ! command -v sfdisk >/dev/null 2>&1; then
    echo "Installing host dependencies (QEMU, mtools, fdisk)..."
    sudo apt-get update -q
    sudo apt-get install -y -q qemu-system-arm mtools fdisk
fi

# 2. Decompress image
echo "Decompressing firmware image..."
gunzip -c "${COMPRESSED_IMG}" > "${IMG_NAME}"

# 3. Find partition offset
echo "Detecting partition offset..."
OFFSET_BYTES=$(python3 -c "
import sys, subprocess, re
out = subprocess.check_output(['sfdisk', '-d', '${IMG_NAME}']).decode()
for line in out.splitlines():
    if 'start=' in line and ('type=' in line or 'uuid=' in line):
        m = re.search(r'start=\s*(\d+)', line)
        if m:
            print(int(m.group(1)) * 512)
            sys.exit(0)
sys.exit(1)
" || {
    echo "ERROR: failed to detect partition offset in ${IMG_NAME}" >&2
    exit 1
})
echo "Partition 1 offset detected: ${OFFSET_BYTES} bytes"

# 4. Generate the smoke test launch script
cat << 'EOF' > "${TEST_LAUNCH_SH}"
#!/bin/sh
echo "========================================="
echo "  Minime Smoke Test (QEMU Emulation)     "
echo "========================================="

sleep 3
PASSED=1
REASON=""

if [ -f /etc/init.d/S60ui ]; then
	if ! mountpoint -q /mnt/system; then
		PASSED=0
		REASON="system.erofs not mounted at /mnt/system"
	fi
fi

if ! mountpoint -q /mnt/sdcard; then
	PASSED=0
	REASON="SD card not mounted at /mnt/sdcard"
fi

if [ $PASSED -eq 1 ]; then
	echo "Running alliumd smoke test..."
	export ALLIUM_SD_ROOT=/mnt/sdcard
	export ALLIUM_BASE_DIR=/mnt/sdcard/.ui
	export ALLIUM_GAMES_DIR=/mnt/sdcard/roms
	export ALLIUM_APPS_DIR=/mnt/sdcard/apps
	export HOME=/mnt/sdcard
	export PATH=/mnt/sdcard/.ui/bin:/usr/bin:/bin
	
	/mnt/sdcard/.ui/bin/alliumd > /tmp/alliumd_test.log 2>&1 &
	ALLIUM_PID=$!
	sleep 3
	kill -0 $ALLIUM_PID 2>/dev/null && kill $ALLIUM_PID
	
	echo "--- ALLIUMD TEST LOGS ---"
	cat /tmp/alliumd_test.log
	echo "-------------------------"
	
	if grep -q -E "cannot open shared object file|so\..*not found|Segmentation fault" /tmp/alliumd_test.log; then
		PASSED=0
		REASON="alliumd crashed or has missing dynamic libraries"
	fi
fi

if [ $PASSED -eq 1 ]; then
	echo "=== SMOKE TEST: PASSED ==="
else
	echo "=== SMOKE TEST: FAILED ($REASON) ==="
fi
echo "========================================="
poweroff -f
EOF
chmod +x "${TEST_LAUNCH_SH}"

# 5. Overwrite .ui/launch.sh inside partition 1 of the image
echo "Injecting smoke test launcher into temporary image..."
MTOOLS_SKIP_CHECK=1 mcopy -o -i "${IMG_NAME}@@${OFFSET_BYTES}" "${TEST_LAUNCH_SH}" ::.ui/launch.sh
rm -f "${TEST_LAUNCH_SH}"

# 6. Run QEMU
echo "Running QEMU system emulation..."
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
