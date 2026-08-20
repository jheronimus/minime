# Storage Architecture & Partition Layout

## Problem
Flash memory wear, abrupt power-offs during gameplay, and filesystem corruption can damage mutable operating system partitions. The userdata card must remain FAT32/exFAT-compatible for user access (ROMs, BIOS, saves), which forbids storing BlueZ's colon-named state directories directly on it.

## Solution
Adopt a two-partition layout:

1. `system.erofs`: High-compression, read-only root filesystem mounted at `/`. Interrupted writes or sudden power cuts cannot corrupt the OS image.
2. `userdata` (partition 1, FAT32): user ROMs, BIOS files, save states, logs, and `.minime/` runtime configurations. Grown to the full card on first boot.

Services that need a Linux-native filesystem for state that FAT cannot represent (e.g. BlueZ's colon-named MAC directories) store it in a small filesystem image file *inside* the FAT card rather than a dedicated partition. This avoids changing the partition table, so it works on already-flashed cards without a reflash. See [0014-bluetooth.md](0014-bluetooth.md) for the Bluetooth state image.

## Examples
- Genimage partition definition: `packages/components/boards/common/genimage.cfg`
- Partition mount/expand logic: `packages/components/boards/common/initramfs-init.sh`
- State image mount: `packages/components/boards/common/overlay/etc/init.d/bluetooth`

## See Also
- Image assembly script: [`packages/image/build.sh`](../../packages/image/build.sh)
- Board partitioning configs: [`packages/components/boards/`](../../packages/components/boards/)
- Bluetooth persistence: [`0014-bluetooth.md`](0014-bluetooth.md)