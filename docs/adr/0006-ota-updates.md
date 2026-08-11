# ADR 0006: OTA Update Package Format and Delivery Workflow

## Status

Accepted

## Context

Minime produces raw bootable SD card images (`.img.zst`) and OTA update packages (`.tar.zst`) in the single CI workflow `build.yml`.

Questions arose regarding OTA behavior and delivery:

1. Will applying an OTA update trigger partition expansion (`first_boot_expand`) on reboot?
2. How can users apply OTA updates before launchers (Allium and MinUI) implement native UI update features?
3. How do updates reach the device, and how is user data (ROMs, BIOS files, save states, configs) guaranteed to be preserved?

## Decision

### 1. Update Package Specification

The update package generator [mkupdate.sh](../../minime/build/mkupdate.sh) packages system binaries **and the active UI payload** into a compressed archive `minime-<target>-<board>-<ui>.tar.zst`.

The archive is a **deliberate mirror of the on-SD payload layout**. It contains strictly:

| Archive entry | Source | Description |
|---------------|--------|-------------|
| `.minime/kernel` | `Image` | Uncompressed Linux kernel binary |
| `.minime/initramfs` | `initramfs.img` | Initramfs CPIO archive containing early init logic |
| `.minime/system` | `system.erofs` | Read-only compressed EROFS root filesystem |
| `.minime/devices/*.dtb` | `*.dtb` | Device Tree Blobs for board hardware variants |
| `.minime/dtb` | default DTB | `boot.cmd`'s fallback DTB, used when `.minime/devices/${device}` is missing (`device` comes from `device.cfg`/U-Boot `fdtfile`; the default is chosen like `mkimage.sh` — `DEFAULT_DEVICE` from `boot.env`, else the first `devices/*.dtb`). Without this entry, DTS-affecting kernel changes silently never deploy over OTA |
| `.minime/ui.env` | UI payload | UI contract manifest (only when a `--ui` is specified) |
| `.minime/manifest.json` | Generated | Build identity: `target`, `board`, `ui`, `minime_commit`, `ui_commit`, `timestamp` |
| `.system/` | UI payload staging | MinUI binaries (`minime/`, `res/`, `version.txt`, `commits.txt`) |

The archive is built with a leading `.` so that **extracting it directly onto `/mnt/sdcard/` places each entry in its final location**:

```sh
unzstd -c minime-alpine-h700-minui.tar.zst | tar -xf - -C /mnt/sdcard/
```

**Nothing else is packaged.** BIOS files, ROMs, save states, emulator paks, `Tools/`, `Emus/`, `.userdata/`, `.minime/config/`, `.minime/traits`, `u-boot-ddr3.bin`, and `boot.log` are deliberately excluded. User data is preserved **by construction** — it never enters the archive — rather than by defensive checks in the delivery script.

### 2. Partition Expansion Safety

OTA updates do not trigger SD card partition expansion:

- [mkimage.sh](../../minime/build/mkimage.sh#L135) creates `/mnt/card/.minime/config/first_boot_expand` only when staging full raw disk images (`.img.zst`).
- [mkupdate.sh](../../minime/build/mkupdate.sh) omits `/mnt/card/.minime/config/first_boot_expand`.
- On first boot after raw image flash, [initramfs-init.sh](../../minime/boards/common/initramfs-init.sh#L91-L150) finds `first_boot_expand` -> resizes partition -> deletes `first_boot_expand`.
- When an OTA update is applied, `first_boot_expand` is not recreated -> [initramfs-init.sh](../../minime/boards/common/initramfs-init.sh#L91) finds no trigger file -> skips partition expansion.

### 3. Delivery Tooling

#### Device-side updates (`/usr/bin/update.sh`)

OTA updates are applied **on the device** by `/usr/bin/update.sh <minui|allium>` (baked into the rootfs overlay). It is invoked over telnet/SSH (e.g. `just remote "update.sh minui"`) and detaches itself so it survives the session:

1. Self-detects board (`/proc/device-tree/compatible`) and target (`/etc/os-release`).
2. Downloads `minime-<target>-<board>-<ui>.tar.zst` from the `testing` GitHub Release with curl.
3. Compares the archive's `.minime/manifest.json` against the installed one; exits early when already current.
4. Stops the UI, then `rm -rf /mnt/sdcard/.system && unzstd -c <pkg> | tar -xf - -C /mnt/sdcard/`.
   - `.system/` is **clean-replaced** — pure UI payload, so no stale binaries linger after a switch.
   - `.minime/` is **overlaid** — the OS payload (including the bootloader's default `.minime/dtb`) is refreshed, while device-specific state (`config/`, `traits`, `u-boot-ddr3.bin`, `boot.log`) is not in the archive and is therefore preserved.
   - Switching UIs (e.g. MinUI → Allium) renames `Roms/` subfolders to the new UI's naming convention via the shared `roms/mappings` table (also consumed by the preloaded-ROM installer).
5. Reboots the device.

There is no host-side OTA push (`just update`). Arbitrary local file uploads use `just upload`; the generic push-and-apply helper [scripts/update-device.sh](../../scripts/update-device.sh) remains for locally built packages (boot-profiler instrumented initramfs).

#### Full image flash (`just deploy`)

`just deploy <os> <board> <ui> [disk]` fetches the latest `minime-<os>-<board>-<ui>.img.zst` and flashes it to the SD card (`dd` / `diskutil`), optionally injecting `wifi.cfg`. It also accepts an explicit image path for flashing a specific build. The `deploy.cfg` `minime`-label guard prevents accidental writes to non-Minime cards.

#### Version check

The device's installed build is read from `/mnt/sdcard/.minime/manifest.json` (build identity written by `mkupdate.sh`) via `just remote "cat /mnt/sdcard/.minime/manifest.json"`. `update.sh` performs the same comparison internally and reports "already up to date" when nothing is pending.

#### Deprecated: `just fetch` / `just update` / `just check-version`

`just fetch`, `just fetch-update`, `just update`, and `just check-version` are removed. `just deploy` fetches the latest testing image on demand; OTA updates are applied on-device via `/usr/bin/update.sh`. There is no longer a separate "download all images" step.

### 4. User Data Ownership

The FAT32 card layout keeps user data separate from updateable system content:

| Path | Owner | Updateable by OTA? |
|------|-------|--------------------|
| `.minime/{kernel,initramfs,system,devices,dtb,ui.env}` | Minime OS + UI contract | Yes (overlaid) |
| `.system/` | Active UI (MinUI/Allium) | Yes (clean-replaced) |
| `.userdata/` | Active UI (upstream MinUI convention) | No — never packaged |
| `Bios/`, `Roms/`, `Saves/`, `Emus/`, `Tools/` | User | No — never packaged |
| `.minime/config/`, `.minime/traits`, `u-boot-ddr3.bin`, `boot.log` | Minime OS device state | No — never packaged |

`.userdata/` is an **upstream MinUI** directory (defined in MinUI's `defines.h` and created at runtime by MinUI's `launch.sh`/`minarch.c` for logs, recents, shader cache, and per-game config/slot state). It is not a Minime invention and is neither shipped in images nor packaged in OTAs.

## Consequences

- OTA archives remain small (typically under 100 MB) because bootloaders, BIOS files, and FAT32 user data are excluded.
- User data, emulator configs, saved states, ROMs, and `.minime/config` are preserved across updates by construction.
- No risk of partition re-expansion or filesystem corruption during system updates.
- `.system/` is replaced wholesale per update; `.minime/` device state persists.
