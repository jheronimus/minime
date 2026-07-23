# ADR 0001: FAT32 Cluster Sizing, Low-Cluster Reservation & Image Sizing Floor

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
When expanding a FAT32 filesystem from ~1 GB to 32 GB – 256 GB at first boot:
- The FAT allocation tables (`FAT1` and `FAT2`) must grow from 512 sectors per FAT to ~15,000 – 131,000 sectors per FAT to index all clusters.
- In FAT32 architecture, data clusters start immediately after `FAT2` (`reserved_sectors + 2 * sectors_per_fat`).
- When preloaded files (such as `.minime/system`) are copied into `userdata.vfat` during image generation, `mcopy` writes them starting at Cluster 2 (sector offset `1056`).
- When `fatresize` attempts to expand `FAT1` and `FAT2` without unallocated low clusters, `FAT1`/`FAT2` expansion collides with Cluster 2 (which `fatresize` cannot relocate), causing `fatresize` to fail with `ERROR: failed to expand /dev/mmcblk0p1`.

---

## Decision

1. **Cluster Size**: Fixed to 16 KB (`mkdosfs -F 32 -s 32` -> 32 sectors per cluster @ 512B/sector).
2. **Low-Cluster Headroom Reservation (`.minime/reserved.bin`)**:
   - During image creation in `03-userdata-vfat.sh`, a 128 MB zero-filled dummy file (`.minime/reserved.bin`) is copied as the **very first file** into `userdata.vfat`.
   - This forces `mcopy` to allocate Cluster 2 .. Cluster 8193 for `reserved.bin`, pushing all real system files (`.minime/system`, `boot.scr`, `Roms`, etc.) to Cluster 8194+ (sector offset `263,200`).
   - On first boot, `initramfs-init.sh` deletes `/mnt/card/.minime/reserved.bin` immediately before invoking `fatresize`.
   - Sectors `1056` through `263,199` become free unallocated clusters, allowing `fatresize` to expand `FAT1` and `FAT2` tables up to 275 GB SD cards without any cluster collision.
3. **Minimum Volume Floor (`VFAT_MB`)**: Hardcoded to **1040 MB** in `03-userdata-vfat.sh` for both Alpine and Buildroot image builders.

---

## Rationale

- **Full Toolchain Compatibility**: Standard `mkdosfs -F 32 -s 32` parameters are preserved. No modification of BPB `reserved_sectors` is required, eliminating `mtools` (`mcopy`) parsing errors.
- **Zero Compressed Size Overhead**: 128 MB of zeroed bytes compresses down to ~100 bytes in LZMA (`.img.xz`), adding zero overhead to release assets.
- **Collision-Free FAT Resizing**: 128 MB of freed low clusters provide guaranteed headroom for `FAT1` and `FAT2` expansion up to 275 GB SD cards.
- **Instant First-Boot Expansion**: `fatresize` expands the filesystem table in milliseconds without relocating data blocks.
