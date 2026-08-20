# Storage Architecture & Partition Layout

## Problem
Flash memory wear, abrupt power-offs during gameplay, and filesystem corruption can damage mutable operating system partitions. The userdata card must remain FAT32/exFAT-compatible for user access (ROMs, BIOS, saves), which forbids storing BlueZ's colon-named state directories directly on it.

## Solution
Adopt a three-partition layout:

1. `system.erofs`: High-compression, read-only root filesystem mounted at `/`. Interrupted writes or sudden power cuts cannot corrupt the OS image.
2. `userdata` (partition 1, FAT32): user ROMs, BIOS files, save states, logs, and `.minime/` runtime configurations. Grown to the full card on first boot.
3. `state` (partition 2, ext4, 4 MB): Linux-native state area for services that cannot store state on FAT. Currently holds BlueZ pairing data at `/var/lib/bluetooth`. Seeded zero-filled at image build time (compresses to ~nothing in the `.img.zst`) and formatted on first use by `init.d/bluetooth`. The first-boot expand grows partition 1 only up to partition 2, never over it.

The state partition is intentionally small: BlueZ state is a few KB per device. Growing it later is not practical (a partition can only grow into free space after it, and FAT32 cannot be shrunk at runtime), so a small fixed size is the smallest-footprint design.

## Examples
- Genimage partition definition: `packages/components/boards/common/genimage.cfg`
- Partition mount/expand logic: `packages/components/boards/common/initramfs-init.sh`
- State partition mount: `packages/components/boards/common/overlay/etc/init.d/bluetooth`

## See Also
- Image assembly script: [`packages/image/build.sh`](../../packages/image/build.sh)
- Board partitioning configs: [`packages/components/boards/`](../../packages/components/boards/)
- Bluetooth persistence: [`0014-bluetooth.md`](0014-bluetooth.md)