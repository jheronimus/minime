# Storage Architecture & Partition Layout

## Problem
Flash memory wear, abrupt power-offs during gameplay, and filesystem corruption can damage mutable operating system partitions.

## Solution
Adopt a robust two-partition layout:
1. `system.erofs`: High-compression, read-only root filesystem mounted at `/`. Interrupted writes or sudden power cuts cannot corrupt the OS image.
2. `userdata`: FAT32 partition containing user ROMs, BIOS files, save states, logs, and `.minime/` runtime configurations.

## Examples
- Genimage partition definition: `packages/components/boards/common/genimage.cfg`
- Partition mount logic: `packages/components/boards/common/initramfs-init.sh`

## See Also
- Image assembly script: [`packages/image/build.sh`](../../packages/image/build.sh)
- Board partitioning configs: [`packages/components/boards/`](../../packages/components/boards/)
