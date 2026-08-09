# 0017: On-Device OTA Update Tool

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
- **Per-UI ROM folder naming.** The same system uses different `Roms/`
  subfolder names per UI — MinUI `"Game Boy (GB)"` vs Allium `"GB"`, per the
  preloaded-ROM installer's mapping — so a UI switch leaves ROMs organized
  for the old UI.

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
(ADR 0006). `update.sh allium` on a MinUI device therefore installs the
Allium payload and, on next boot, `init.d/ui` reads the overlaid `ui.env`
and launches Allium. `update.sh` reads the *pre-switch* installed UI from
`ui.env` before applying, since the archive overwrites it.

### 3. Detached by default (telnet-safe)

`update.sh` re-executes itself under `setsid` with stdio redirected to
`/mnt/sdcard/.minime/update/update.log` (SD card, survives reboot) and returns
immediately. A pidfile guards against concurrent runs. This survives the
invoking telnet session dropping — the previous host-side flow had to
background the extraction and poll for a completion marker for the same
reason (ADR 0006 §3).

### 4. Roms/ subfolder rename on UI switch

The preloaded-ROM folder mapping was extracted into a single shared table
[roms/mappings](../../roms/mappings) (`short|minui_name|allium_name`),
consumed by both:

- [roms/install.sh](../../roms/install.sh) at build time (per-UI ROM staging),
- `update.sh` at runtime, via the copy baked into the rootfs as
  `/usr/share/minime/rom-mappings` by both `post-build.sh` scripts.

On a UI switch, `update.sh` renames each known `Roms/` subfolder to the new
UI's name **only when the target name does not already exist** — it never
nests or clobbers. Only the 14 preloaded systems are in the table; user-added
folders are left untouched (Allium's mapper matches by substring, so most
still resolve).

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
  (`minime.local`, ADR 0018) or IP via `just remote`.
- The device must reach GitHub over HTTPS to download the archive; it already
  ships curl + CA certificates on both targets.
- The updater ships in the rootfs overlay and is itself replaced by the OTA
  payload it installs — no bootstrapping problem.
- ROM renames cover preloaded systems only; switching preserves all user data
  and per-UI private state (`.userdata/` vs `.allium/`) by never touching them.

## Reference

- On-device updater: `minime/boards/common/overlay/usr/bin/update.sh`.
- Shared mapping: `roms/mappings`, `roms/install.sh`,
  `minime/targets/alpine/scripts/post-build.sh`,
  `minime/targets/buildroot/external/scripts/post-build.sh`.
- Related: `docs/adr/0006-ota-updates.md` (archive format), `docs/adr/0013-network-services-passwordless.md`
  (telnet/FTP model), `docs/adr/0018-mDNS-self-announcement.md` (name resolution).
