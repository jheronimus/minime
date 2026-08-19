# On-Device Atomic OTA Updates

## Problem
Updating firmware over the network on handheld devices can brick the system if the connection drops, storage runs out of space, or interrupted writes leave partial binaries in the boot partition.

## Solution
OTA updates use an atomic `.tar.zst` payload containing the `.minime/` OS bundle and `.system/` UI assets. Update installation runs on-device via `/usr/bin/update.sh` (detached from the terminal session), verifies free storage space and archive checksums, applies updates cleanly, preserves user configuration, and syncs before rebooting.

## Examples
- Trigger update from host: `just ota minui`
- Direct on-device execution: `update.sh minui`

## See Also
- On-device update script: [`packages/components/boards/common/overlay/usr/bin/update.sh`](../../packages/components/boards/common/overlay/usr/bin/update.sh)
- Update package builder: [`packages/image/build.sh`](../../packages/image/build.sh)
