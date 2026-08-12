# ADR 0001: FAT32 Cluster Sizing & Image Sizing Floor

## Status
Accepted

## Context
Minime produces raw bootable SD card disk images (`.img.zst`) containing bootloader partitions and a primary FAT32 user data partition (`userdata.vfat`). On first boot, a runtime initramfs script expands the FAT32 partition to 100% of the target SD card.

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

Because $65,503 < 65,525$, all OS/U-Boot FAT drivers classify the volume as **FAT16** while `mkdosfs -F 32` writes FAT32 BPB headers — a fatal BPB/cluster mismatch that makes the filesystem unreadable by U-Boot and host OSes.

## Decision
1. **Cluster Size**: Fixed to 16 KB (`mkdosfs -F 32 -s 32` -> 32 sectors per cluster @ 512B/sector).
2. **Minimum Volume Floor (`VFAT_MB`)**: Hardcoded to **1040 MB** in `minime/build/mkimage.sh` for both Alpine and Buildroot image builders.

At 1040 MB ($1,090,519,040$ bytes), cluster count is $\mathbf{66,527\text{ clusters}} \ge 65,525$, producing a perfectly valid FAT32 volume.

## Partition Mapping (H700 vs RK3326/RK3566)
Minime must support heterogeneous SoC families with diverging partition table requirements:
- **RK3326 / RK3566**: Requires a GPT partition table. Bootloader components reside in raw unpartitioned space before sector 32768, followed by `boot` and `userdata` GPT partitions. RK3566 uses the upstream chain (`idbloader.img`, `u-boot.itb`); RK3326 uses the vendor Rockchip chain (`idbloader.img` at 32K, `uboot.img` at 8M, `trust.img` at 12M — see `minime/boards/rk3326/genimage.cfg`).
- **H700 / Allwinner**: Enforces a legacy MBR partition table. Bootloader (`u-boot-sunxi-with-spl.bin`) resides in unpartitioned space starting at sector 16, overlapping with standard GPT headers. `userdata` is an MBR partition.

To unify infrastructure, `genimage.cfg` uses conditional includes. RK3326/RK3566 include `board/common/genimage.cfg` to emit GPT images, while H700 provides its own `board/h700/genimage.cfg` overriding to MBR.

## First-Boot Expansion
Minime ships a small seeded FAT32 (1040 MB floor, ~246 MB used) so the image fits on any SD card. On first boot, an initramfs script (`first_boot_expand`) grows the `userdata` partition to 100% of the card and recreates the FAT32 at full size.

The initramfs performs the following steps, mirroring the approach used by EmuELEC, dArkOS, and fraggod's RPi FAT32 resize script:

1. `parted resizepart` grows the `userdata` partition to 100% of the SD card.
2. All FAT contents (`.minime`, `.system`, `boot.scr`, config, etc. — ~246 MB) are staged into a RAM-backed tmpfs (`/tmp/stage`, 512 MB).
3. The EROFS system image is re-mounted from the staged copy so the tools survive the wipe.
4. `mkfs.vfat -F 32 -s 32 -n minime` wipes and recreates the FAT32 at the full resized partition size.
5. Staged contents are restored, `.minime`/`.system` re-hidden, the `first_boot_expand` marker removed, and the device reboots.

### Why not `fatresize`
FAT32 cannot be grown in place reliably: libparted cannot end a resize at the very last sector (assertion failures in `fatresize.c:347`), and growing a volume that needs FAT-table relocation requires geometry-dependent slack (16-64 MB). Reference projects hit the same wall (teslausb pads 64 KiB; Tails caps at `partition_size - 2 MiB`). Recreating with `mkfs.vfat` sidesteps this entirely and is the proven single-FAT32 firmware pattern. (An earlier `fatresize -i` flag misuse that probed the whole disk was also corrected to `-n` before fatresize was removed.)

## Rationale
- **Hardware NAND Flash Alignment**: 16 KB cluster size matches 16 KB NAND flash page sizes on modern SD cards, preventing write amplification and minimizing random read latency.
- **Directory Read Performance**: 16 KB clusters reduce FAT table lookup entries by $4\times$ compared to 4 KB clusters, accelerating launcher directory scans in MinUI and Allium.
- **Specification Compliance**: 1040 MB is the absolute minimum boundary required for a valid 16 KB cluster FAT32 volume.

