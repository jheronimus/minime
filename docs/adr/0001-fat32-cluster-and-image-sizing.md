# ADR 0001: FAT32 Cluster Sizing & Image Sizing Floor

## Status
Accepted

## Context
Minime produces raw bootable SD card disk images (`.img.xz`) containing bootloader partitions and a primary FAT32 user data partition (`userdata.vfat`). On first boot, a runtime initramfs script expands the FAT32 partition to 100% of the target SD card.

When evaluating minimum image sizing, `VFAT_MB` was briefly dropped from 1040 MB to 1024 MB. This resulted in complete boot failures (black screen / no backlight on RG35xxSP v1) and volume mount failures on macOS/Linux/bootloaders.

## Root Cause Analysis
Microsoft FAT32 Specification (Section 3.5) defines FAT volume types strictly by cluster count:
- If $\text{CountOfClusters} < 4085$, volume is FAT12.
- If $4085 \le \text{CountOfClusters} < 65525$, volume is **FAT16**.
- If $\text{CountOfClusters} \ge 65525$, volume is **FAT32**.

When `mkdosfs -F 32 -s 32` was invoked on a `1024 MB` raw volume ($1,073,741,824$ bytes):
1. Total Sectors = 2,097,152.
2. Reserved Sectors = 32; FAT1 + FAT2 tables = 1,024 sectors.
3. Usable Data Sectors = $2,097,152 - 32 - 1024 = 2,096,096$ sectors.
4. Usable Cluster Count = $2,096,096 / 32 = \mathbf{65,503\text{ clusters}}$.

Because $65,503 < 65,525$, all OS filesystem drivers (macOS `msdos`, Linux `fs/fat`, U-Boot `fs/fat`) classify the volume as **FAT16**, while the BPB structure written by `mkdosfs -F 32` contains 32-bit FAT32 headers. This causes severe BPB/cluster mismatch, rendering the filesystem unreadable by U-Boot and host operating systems.

## Decision
1. **Cluster Size**: Fixed to 16 KB (`mkdosfs -F 32 -s 32` -> 32 sectors per cluster @ 512B/sector).
2. **Minimum Volume Floor (`VFAT_MB`)**: Hardcoded to **1040 MB** in `post-image.sh` for both Alpine and Buildroot image builders.

At 1040 MB ($1,090,519,040$ bytes), cluster count is $\mathbf{66,527\text{ clusters}} \ge 65,525$, producing a perfectly valid FAT32 volume.

## Rationale
- **Hardware NAND Flash Alignment**: 16 KB cluster size matches 16 KB NAND flash page sizes on modern SD cards, preventing write amplification and minimizing random read latency.
- **Directory Read Performance**: 16 KB clusters reduce FAT table lookup entries by $4\times$ compared to 4 KB clusters, accelerating launcher directory scans in MinUI and Allium.
- **Specification Compliance**: 1040 MB is the absolute minimum boundary required for a valid 16 KB cluster FAT32 volume.

