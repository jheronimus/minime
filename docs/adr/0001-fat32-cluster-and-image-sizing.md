# ADR 0001: FAT32 Cluster Sizing & Image Sizing Floor

## Status
Accepted

## Context
Minime produces raw bootable SD card disk images (`.img.xz`) containing bootloader partitions and a primary FAT32 user data partition (`userdata.vfat`). On first boot, a runtime initramfs script expands the FAT32 partition to 100% of the target SD card.

Previously, `post-image.sh` hardcoded a 1040 MB floor and produced ~1.04–2.0 GB uncompressed images. With the removal of large/unsupported ROM bundles (Sega Saturn, Neo Geo CD, Arcade), staged filesystem payload size dropped to ~367 MB.

We needed to evaluate optimal cluster size and minimum image volume bounds to minimize SD card flashing times (`dd`) while maintaining peak runtime file access performance on handheld hardware.

## Decision
1. **Cluster Size**: Fixed to 16 KB (`mkdosfs -F 32 -s 32` -> 32 sectors per cluster @ 512B/sector).
2. **Minimum Volume Floor (`VFAT_MB`)**: Fixed to 1024 MB (1 GiB) in `post-image.sh` for both Alpine and Buildroot image builders.

## Rationale

### 1. NAND Flash Alignment & Hardware Performance
Modern SDHC/SDXC flash cards utilize 16 KB NAND flash page sizes. Setting cluster size to 16 KB matching the hardware page size prevents read-modify-write cycles (write amplification) and minimizes random read latency when loading ROMs, executables, and assets.

### 2. FAT Table Footprint & Directory Reading Speed
Compared to default 4 KB clusters (`-s 8`), 16 KB clusters reduce File Allocation Table (FAT) entry overhead by $4\times$. This dramatically speeds up directory enumeration in handheld launchers (MinUI / Allium) when navigating folders containing hundreds of ROMs.

### 3. FAT32 Specification Constraints
The FAT32 specification requires a minimum of 65,525 clusters (0xFFF5) to be recognized as a valid FAT32 volume by operating systems and bootloaders:
$$\text{Min Volume Size} = 65,525 \times 16\text{ KB} = 1,048,400\text{ KB} \approx 1024\text{ MB}$$
Setting `VFAT_MB=1024` produces exactly 65,536 clusters, satisfying the FAT32 spec floor while producing the smallest possible flashable disk image (~1.04 GB raw / ~140–200 MB compressed).
