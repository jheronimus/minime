# ADR 0003: On-Device OTA Update Tool

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

OTA delivery was originally host-pushed via `just update <os> <board> <ui>`
([scripts/update-device.sh](../../scripts/update-device.sh)). This required the host
to track board, target, UI, and dynamic DHCP IP (`deploy.cfg`).

The on-device updater [update.sh](../../minime/boards/common/overlay/usr/bin/update.sh)
is the single OTA path. Requirements:
- **Switch UIs & Targets without reflashing.** Switching between MinUI/Allium or
  Alpine/Buildroot must not require rewriting the SD card.
- **Canonical ROM folder naming.** Both UIs share one canonical naming scheme (§4).

## Decision

### 1. The on-device updater is the single OTA path

[update.sh](../../minime/boards/common/overlay/usr/bin/update.sh) takes optional
`[alpine|buildroot]` and `[minui|allium]` arguments and self-detects anything omitted:
- **Board** from `/proc/device-tree/compatible`, with staged `.minime/dtb` fallback.
- **Target** from `/etc/os-release`, with `gpu_driver` trait fallback.
- **UI** from `/mnt/sdcard/.minime/ui.env`, with `minui` fallback.

It downloads `minime-<target>-<board>-<ui>.tar.zst` from GitHub `testing`, diffs
`.minime/manifest.json` against the installed build (exits early if current),
stops the UI, applies (`.system` clean-replaced, `.minime` overlaid), and reboots.

### 2. UI and Target switching without reflashing

The OTA archive carries `.minime/ui.env`, the full OS payload (`kernel`,
`initramfs`, `system.erofs`, DTBs), and UI binaries (ADR 0002). `update.sh allium`
or `update.sh buildroot` installs the requested payload. On next boot, `init.d/ui`
reads the overlaid `ui.env` and traits regenerate if `gpu_driver` changed.
`update.sh` reads the pre-switch UI before applying to clean up stale dirs.

### 3. Detached by default (telnet-safe)

`update.sh` runs under `setsid` with logs redirected to `/mnt/sdcard/.minime/update/update.log`
and returns immediately. A pidfile guards against concurrent runs.

### 4. Roms/ folders use one canonical (MinUI) naming scheme

Both UIs share a single set of `Roms/` folder names ([roms/mappings](../../roms/mappings)).
There is no Roms rename on UI switch — user data is preserved by construction.

### 5. Host-side OTA tooling removed

- `just update` and `just check-version` removed.
- [scripts/update-device.sh](../../scripts/update-device.sh) is retained only for local custom package pushes.
- Verify status with `just shell "cat /mnt/sdcard/.minime/manifest.json"`.

## Consequences

- No hardcoded target IP needed: device is reached by mDNS (`minime.local`) or IP via `just shell`.
- OTA updates replace kernel, initramfs, rootfs (`system.erofs`), and UI payload atomically.
- User data (`Bios/`, `Roms/`, `Saves/`, `.userdata/`) is preserved across target and UI switches.

## Reference

- Updater: `minime/boards/common/overlay/usr/bin/update.sh`.
- Mapping: `roms/mappings`, `roms/install.sh`.
- Related: `docs/adr/0002-ota-package-format.md`, `docs/adr/0016-network-services-passwordless.md`, `docs/adr/0017-mdns-self-announcement.md`.
