# ADR 0003: On-Device OTA Update Tool

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

OTA delivery was originally **host-pushed**: `just update <os> <board> <ui>`
fetched the latest `testing` archive and pushed it to the device over
FTP/telnet via [scripts/update-device.sh](../../scripts/update-device.sh). This
forced the host to know three things about the device — its **board** (SoC),
its **target** (alpine/buildroot), and which **UI** it runs — plus a
reachable **IP**, which is dynamic under DHCP and had to be hardcoded in
`deploy.cfg` (`target_ip=...`).

The on-device updater [update.sh](../../minime/boards/common/overlay/usr/bin/update.sh)
already existed (formerly `minime-update.sh`) but was secondary. Two
unresolved requirements remained:

- **Switch UIs without reflashing.** MinUI and Allium are mutually exclusive
  UI payloads; switching meant reflashing the SD card.
- **Per-UI ROM folder naming.** The same system used different `Roms/`
  subfolder names per UI — MinUI `"Game Boy (GB)"` vs Allium `"GB"` — so a
  UI switch left ROMs organized for the old UI. **Resolved in 2026-08-11:**
  both UIs share one canonical naming scheme (§4).

## Decision

### 1. The on-device updater is the single OTA path

[update.sh](../../minime/boards/common/overlay/usr/bin/update.sh) takes a
single argument `<minui|allium>` and self-detects everything else:

- **Board** from `/proc/device-tree/compatible` (`sun50i-h700`/`rk3326`/
  `rk3566`), with the staged `.minime/dtb` filename as fallback.
- **Target** from `/etc/os-release` (`ID=alpine`/`buildroot`), with the
  `gpu_driver` trait as fallback.

It downloads `minime-<target>-<board>-<ui>.tar.zst` from the GitHub
`testing` release, compares the archive's `.minime/manifest.json` against the
installed one (exits early when already current), stops the UI, applies
(`.system` clean-replaced, `.minime` overlaid), and reboots.

### 2. UI switching without reflashing

The OTA archive carries `.minime/ui.env` and the UI payload `.system/`
(ADR 0002). `update.sh allium` on a MinUI device therefore installs the
Allium payload and, on next boot, `init.d/ui` reads the overlaid `ui.env`
and launches Allium. `update.sh` reads the *pre-switch* installed UI from
`ui.env` before applying, since the archive overwrites it.

### 3. Detached by default (telnet-safe)

`update.sh` re-executes itself under `setsid` with stdio redirected to
`/mnt/sdcard/.minime/update/update.log` (SD card, survives reboot) and returns
immediately. A pidfile guards against concurrent runs. This survives the
invoking telnet session dropping — the previous host-side flow had to
background the extraction and poll for a completion marker for the same
reason (ADR 0002 §3).

### 4. Roms/ folders use one canonical (MinUI) naming scheme

Both UIs share a single set of `Roms/` folder names, mirroring MinUI's
canonical names (`"Game Boy (GB)"`, `"Sega Master System (SMS)"`, …). The
preloaded-ROM mapping [roms/mappings](../../roms/mappings) is therefore a
two-column table (`short_name|roms_dir`) consumed only at build time by
[roms/install.sh](../../roms/install.sh). Allium resolves roms by the
`(ABBREV)` tag in the folder name, so it needs no separate naming scheme.

Consequence: there is **no Roms rename on UI switch** — `update.sh` installs
the payload and never touches `Roms/` folders. The on-device
`/usr/share/minime/rom-mappings` table and the `rename_roms()` logic were
removed from `update.sh` and both `post-build.sh` scripts.

### 5. Host-side OTA tooling removed

- `just update` and `just check-version` recipes removed; `scripts/check-version.sh`
  deleted. `update.sh`'s internal manifest diff subsumes the version check.
- [scripts/update-device.sh](../../scripts/update-device.sh) is **retained**
  as a generic push-and-apply helper for locally built packages (the
  boot-profiler's instrumented initramfs, `scripts/boot-profile.sh`).
- `just upload` (FTP) is the arbitrary-file upload path.
- Verify a device is current with `just remote "cat /mnt/sdcard/.minime/manifest.json"`.

## Consequences

- No IP/hardcoding needed for updates: reach the device by mDNS name
  (`minime.local`, ADR 0017) or IP via `just remote`.
- The device must reach GitHub over HTTPS to download the archive; it already
  ships curl + CA certificates on both targets.
- The updater ships in the rootfs overlay and is itself replaced by the OTA
  payload it installs — no bootstrapping problem.
- Both UIs share one canonical `Roms/` naming, so switching preserves all user
  data and per-UI private state (`.userdata/` vs `.allium/`) by never touching
  them, and there is no rename step to get wrong.

## Reference

- On-device updater: `minime/boards/common/overlay/usr/bin/update.sh`.
- Shared mapping: `roms/mappings`, `roms/install.sh`.
- Related: `docs/adr/0002-ota-package-format.md` (archive format), `docs/adr/0016-network-services-passwordless.md`
  (telnet/FTP model), `docs/adr/0017-mdns-self-announcement.md` (name resolution).
