# ADR 0001: FAT32 Cluster Sizing, Reserved Headroom & Image Sizing Floor

## Status
Accepted

## Context
Minime produces raw bootable SD card disk images (`.img.xz`) containing bootloader partitions and a primary FAT32 user data partition (`userdata.vfat`). On first boot, a runtime initramfs script expands the FAT32 partition to 100% of the target SD card.

### FAT32 Specifications & Minimum Sizing
Microsoft FAT32 Specification (Section 3.5) defines FAT volume types strictly by cluster count:
- If $\text{CountOfClusters} < 4085$, volume is FAT12.
- If $4085 \le \text{CountOfClusters} < 65525$, volume is **FAT16**.
- If $\text{CountOfClusters} \ge 65525$, volume is **FAT32**.

When `mkdosfs -F 32 -s 32` was invoked on a `1024 MB` raw volume ($1,073,741,824$ bytes):
1. Total Sectors = 2,097,152.
2. Reserved Sectors = 32; FAT1 + FAT2 tables = 1,024 sectors.
3. Usable Data Sectors = $2,097,152 - 32 - 1024 = 2,096,096$ sectors.
4. Usable Cluster Count = $2,096,096 / 32 = \mathbf{65,503\text{ clusters}}$.

Because $65,503 < 65,525$, all OS filesystem drivers (macOS `msdos`, Linux `fs/fat`, U-Boot `fs/fat`) classify the volume as **FAT16**, while the BPB structure written by `mkdosfs -F 32` contains 32-bit FAT32 headers. This causes severe BPB/cluster mismatch, rendering the filesystem unreadable.

### FAT32 Expansion & Cluster Collision Root Cause
When expanding a FAT32 filesystem from ~1 GB to 32 GB – 64 GB at first boot:
- The FAT allocation tables (`FAT1` and `FAT2`) must grow from ~512 sectors per FAT to ~15,000 – 32,000 sectors per FAT to index all clusters.
- In FAT32 architecture, data clusters start immediately after `FAT2` (`reserved_sectors + 2 * sectors_per_fat`).
- When preloaded files (such as `.minime/system`) are copied into `userdata.vfat` during image generation, Cluster 2 is written starting at sector offset `1056`.
- If `fatresize` attempts to expand `FAT1` and `FAT2` without pre-allocated reserved headroom, `FAT1`/`FAT2` expansion collides with Cluster 2 (which `fatresize` cannot relocate), causing `fatresize` to fail with `ERROR: failed to expand /dev/mmcblk0p1`.

---

## Decision

1. **Cluster Size**: Fixed to 16 KB (`mkdosfs -F 32 -s 32` -> 32 sectors per cluster @ 512B/sector).
2. **FAT Reserved Headroom (`-R 65520`)**: Formatted with **65,520 reserved sectors** (32.7 MB reserved headroom, the maximum valid 16-bit value supported in FAT32 BPB headers) via `mkdosfs -F 32 -s 32 -R 65520`.
3. **Minimum Volume Floor (`VFAT_MB`)**: Hardcoded to **1080 MB** in `03-userdata-vfat.sh` for both Alpine and Buildroot image builders.

With `VFAT_MB = 1080 MB` and `-R 65520`, usable cluster count is $\mathbf{67,072\text{ clusters}} \ge 65,525$, producing a valid FAT32 volume.

---

## Rationale

- **Collision-Free FAT Resizing**: 65,520 reserved sectors provide pre-allocated headroom for `FAT1` and `FAT2` to expand up to 68 GB SD cards without colliding with Cluster 2 or moving data files.
- **Specification Compliance**: Reserved sector count stays within the 16-bit BPB limit (`uint16_t` max 65535 in `dosfstools`/`mkfs.fat`).
- **Instant First-Boot Expansion**: `fatresize` expands the filesystem table in milliseconds without relocating data blocks.
- **Hardware NAND Flash Alignment**: 16 KB cluster size matches 16 KB NAND flash page sizes on modern SD cards, preventing write amplification and minimizing random read latency.
