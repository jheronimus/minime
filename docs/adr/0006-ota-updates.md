# ADR 0006: OTA Update Package Format and Manual Upgrade Workflow

## Status

Accepted

## Context

Minime produces raw bootable SD card images (`.img.xz`) and OTA update packages (`.tar.xz`) in the single CI workflow `build.yml`.

Questions arose regarding system behavior during OTA updates:
1. Will applying an OTA update trigger partition expansion (`first_boot_expand`) on reboot?
2. How can users apply OTA updates before launchers (Allium and MinUI) implement native UI update features?

## Decision

### 1. Update Package Specification

The update package generator [mkupdate.sh](file:///Users/ilembitov/Projects/minime/minime/build/mkupdate.sh) packages system binaries into a compressed archive `minime-<target>-<board>[-<ui>].tar.xz`.

The archive contains strictly:

| Artifact | Source File | Description |
|----------|-------------|-------------|
| `kernel` | `Image` | Uncompressed Linux kernel binary |
| `initramfs` | `initramfs.img` | Initramfs CPIO archive containing early init logic |
| `system` | `system.erofs` | Read-only compressed EROFS root filesystem |
| `devices/` | `*.dtb` | Device Tree Blobs for board hardware variants |
| `manifest.json` | Generated | Update metadata (`target`, `board`, `ui`, `timestamp`) |

### 2. Partition Expansion Safety

OTA updates do not trigger SD card partition expansion:

- [mkimage.sh](file:///Users/ilembitov/Projects/minime/minime/build/mkimage.sh#L135) creates `/mnt/card/.minime/config/first_boot_expand` only when staging full raw disk images (`.img.xz`).
- [mkupdate.sh](file:///Users/ilembitov/Projects/minime/minime/build/mkupdate.sh) omits `/mnt/card/.minime/config/first_boot_expand`.
- On first boot after raw image flash, [initramfs-init.sh](file:///Users/ilembitov/Projects/minime/minime/boards/common/initramfs-init.sh#L91-L150) finds `first_boot_expand` -> resizes partition -> deletes `first_boot_expand`.
- When an OTA update is applied, `first_boot_expand` is not recreated -> [initramfs-init.sh](file:///Users/ilembitov/Projects/minime/minime/boards/common/initramfs-init.sh#L91) finds no trigger file -> skips partition expansion.

### 3. Manual Upgrade Workflow

Until Allium or MinUI launcher ports implement native update UI flows, users can update existing installations manually:

1. Download update package `minime-<target>-<board>[-<ui>].tar.xz` from GitHub Releases.
2. Mount the SD card on a host computer or access `/mnt/card` via telnet/FTP.
3. Extract archive contents directly into `.minime/` on the FAT32 SD card partition:
   ```sh
   tar -xf minime-alpine-h700-allium.tar.xz -C /path/to/sdcard/.minime/
   ```
4. Safely unmount and insert SD card into device.
5. Reboot device -> `initramfs-init.sh` mounts updated `kernel`, `initramfs`, and `system.erofs` automatically.

## Consequences

- OTA archives remain small (typically under 100 MB) because bootloaders and FAT32 user data files are excluded.
- User data, emulator configs, saved states, and ROMs on FAT32 partition are preserved across updates.
- No risk of partition re-expansion or filesystem corruption during system updates.
