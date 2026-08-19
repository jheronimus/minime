---
name: live-test
description: Use when deploying updated Minime binaries to the physical handheld over OTA, verifying a change on real hardware, collecting device logs, or debugging an on-device failure. Covers the on-device updater (`update.sh`), `just shell`/`just upload`/`just deploy`, the device log locations (boot.log, per-system emulator logs, ui.log, wifi diagnostics, update log), and the 5 Whys debugging workflow. Triggers: "deploy to device", "test on hardware", "does it work on the device", "verify on-device", "collect logs from the device", "why doesn't X work on the device".
---

# Live Testing on Physical Hardware

Minime's [On-Device Live Verification](../../../AGENTS.md) directive requires that **every code change is deployed to the real handheld and verified empirically** — never assumed from a clean build. This skill is the procedure for delivering updates, collecting evidence, and debugging on-device failures.

## When to use

- After committing + CI-building any change that touches firmware, UI, cores, traits, or initramfs.
- When a user reports an on-device symptom (game won't start, wrong colors, no WiFi, hangs).
- When the CI build succeeded but you have not confirmed behavior on hardware.

## Prerequisites

- Device is powered on and on the same LAN as the dev machine.
- `deploy.cfg` exists in the repo root with `target_ip=...` (and `disk_device=...` for reflashing). Copy `deploy_sample.cfg` if missing. Devices announce themselves over mDNS, so `target_ip=minime.local` works (a second device that conflicts becomes `minime-2.local`).
- A push to `main` has triggered a successful `Build Minime` run and updated the `testing` GitHub Release (check `gh run list` and the release asset timestamps).

---

## 1. Confirm the device is current

```sh
just shell "cat /mnt/sdcard/.minime/manifest.json"     # minime_commit / ui_commit / timestamp
```

The installed build identity is the device's `/mnt/sdcard/.minime/manifest.json` (written by the OTA packager). Let `update.sh` decide whether an update is pending — it diffs the archive manifest against this file itself and reports "already up to date" when nothing changed.

## 2. Deploy updated binaries OTA

The device updates itself from the GitHub `testing` release:

```sh
just shell "update.sh minui"     # or: update.sh allium, or update.sh buildroot — switch UI or OS without reflashing
```

What it does (see `packages/components/boards/common/overlay/usr/bin/update.sh`):

1. **Self-detects** board (`/proc/device-tree/compatible`) and any omitted target (`/etc/os-release`) or UI (`.packages/ui.env`).
2. **Detaches** (`setsid`) so it survives the telnet session dropping; logs to `/mnt/sdcard/.minime/update/update.log`.
3. **Downloads** `minime-<target>-<board>-<ui>.tar.zst` from the `testing` release with curl.
4. **Compares** the archive's `.minime/manifest.json` against the installed one; exits early if already current.
5. **Stops the UI**, clean-replaces the UI payload (`.system/` or `.ui/`), overlays `.minime/` (device state kept).
6. **Preserves user data** (`Bios/`, `Roms/`, `Saves/`, `.userdata/`) and safely migrates legacy ROM folder names.
7. **Reboots** the device.

Watch progress / confirm afterwards:

```sh
just shell "tail -n 40 /mnt/sdcard/.minime/update/update.log"
just shell "cat /mnt/sdcard/.minime/manifest.json"     # new minime_commit / ui_commit
```

Delivery semantics:
- `.system/` is **clean-replaced** — the UI payload, avoids stale files.
- `.minime/` is **overlaid** — device state (`config/`, `traits`, dtb) is preserved.
- **User data is never touched** (`Bios/`, `Roms/`, `Saves/`, `.userdata/`) except the Roms/ folder-name rename when switching UIs.

## 3. Inspect the device

```sh
just shell "uptime"                     # device reachable, fresh boot
just shell "cat /mnt/sdcard/.minime/manifest.json"
just shell "ps | grep -E 'minui|minarch|keymon' | grep -v grep"
```

- After an OTA, `uptime` should be low (fresh reboot).
- A healthy device runs `launch.sh`, `keymon.elf`, `minui.elf` — **not** stray `minarch.elf` instances (a leftover manual minarch run renders on top of the UI and garbles the screen).

## 4. Full reflash (when OTA is not enough)

OTA updates `.minime/` and `.system/` but not the partition layout or bootloader. For kernel/bootloader/partition changes, reflash:

```sh
just deploy alpine h700 minui            # uses deploy.cfg disk_device
# or with an explicit image:
just deploy ./downloads/minime-alpine-h700-minui.img
```

`just deploy` writes the image with `dd`, **injects `wifi.cfg`** if present in the repo root, and ejects the card. The `deploy.cfg` auto-path is **guarded**: it only proceeds if the target disk already has a partition labeled `minime`.

---

## 5. Device log locations

Collect logs via `just shell "cat <path>"` or `just shell "tail -n 100 <path>"`.

| Log | Path | Contents |
|---|---|---|
| Initramfs + boot log | `/mnt/sdcard/.minime/logs/<boot-id>/boot.log` | `[INITRAMFS]` / `[WIFI]` / `[UI]` / `[TRAITS]` lines: partition expansion, EROFS mount, wifi handshake, launcher execution. First place to check. The active boot-id is in `/mnt/sdcard/.minime/logs/current`; the dir also holds `kernel.log` and `syslog.log`. |
| Launcher (minui) log | `/mnt/sdcard/.userdata/minime/logs/minui.txt` | MinUI launcher stdout/stderr (`minui.elf > $LOGS_PATH/minui.txt 2>&1`). |
| Per-system emulator logs | `/mnt/sdcard/.userdata/minime/logs/<TAG>.txt` | `minarch.elf` output per console, e.g. `FC.txt` (NES), `GBA.txt`, `PS.txt`, `SMS.txt`, `MD.txt`, `GG.txt`, `NGP.txt`, `PCE.txt`. Contains `rom_path`, core version, `aspect_ratio`, `selectScaler`, ALSA errors, **`Error relocating ... symbol not found` / `Segmentation fault`** on dlopen failure. |
| UI runtime log | `/tmp/ui.log` | Current UI session (empty when fine). |
| WiFi diagnostics | `/tmp/wifi.diagnostics` (copied to `/mnt/sdcard/wifi.diagnostics` on failure) | Written by the wifi OpenRC service on startup failure: interface presence, SDIO devices, `wpa_cli status`. |
| OTA update log | `/mnt/sdcard/.minime/update/update.log` | `update.sh` progress: board/target/UI detection, download size, manifest compare, install + Roms rename. Written detached (survives reboot — `/tmp` is tmpfs). |
| Build identity | `/mnt/sdcard/.minime/manifest.json` | `minime_commit`, `ui_commit`, `timestamp` — verify which build is running. |

Example: a broken core shows this in `<TAG>.txt`:
```
[INFO] Core_open
[ERROR] Error relocating /mnt/sdcard/.system/minime/cores/picodrive_libretro.so: emu_32x_startup: symbol not found
Segmentation fault
```

## 6. Upload files to the device

```sh
just upload ./local/script.sh script.sh   # copies to /mnt/sdcard (scp default)
just shell "cp /mnt/sdcard/script.sh /tmp/ && sh /tmp/script.sh"
```

Uploads land in the FTP root (`/mnt/sdcard/`). To run a multi-line or quoting-sensitive script, write it locally, upload it, copy to `/tmp`, and execute there — inline commands over telnet mangle quotes/spaces.

---

## 7. The 5 Whys workflow for on-device bugs

When something fails on the device, drive the diagnosis to a **root cause with evidence** rather than a guess. State the issue, then ask "why" at least five times, backing each level with logs or artifacts.

**How to run it:**

1. **State the issue precisely** (e.g. "SMS/GG games don't start on the device").
2. **Why 1 — collect the direct evidence.** Pull the relevant log (`<TAG>.txt`, `boot.log`). The failure line *is* Why 1: `Error relocating ... symbol not found`.
3. **Why 2 — trace the symptom to a component.** Missing symbol → the core `.so` lacks its libretro API.
4. **Why 3 — trace to a build/decision.** Inspect the artifact (`nm -D` / `strings` on the `.so`), the CI link command, the makefile. Note the contradiction when local vs CI differ.
5. **Why 4 — isolate the environment difference.** Compare local build vs CI: flags, ccache, clone depth, submodule state, artifacts. **Prove** each candidate (e.g. build locally with `-j4` to rule it in/out) instead of assuming.
6. **Why 5 — the root cause.** Only accept a cause you can reproduce or back with an artifact.

**Rules of evidence:**
- A hypothesis is only "confirmed" with a log line, `nm`/`strings` output, a build command, or an artifact — never from memory.
- When a fix provably doesn't change the outcome, say so and revert it; record it in the plan doc as "attempted, ineffective".
- Distinguish "introduced by this change" from "pre-existing but only now visible" (e.g. a liblz4 fix made games launch, which then exposed an older broken-core CI issue). Check `git log` dates and blame before attributing.
- Record the full 5-Whys chain in `.scratch/minui-migration-plan.md` (or the relevant doc) so the next session inherits the evidence, not the guessing.

**Worked example (from the session):**
1. SMS/GG/Genesis/PSX don't start → `<TAG>.txt` shows `Error relocating ... symbol not found` / `Segmentation fault`.
2. Missing symbols → `nm -D` on the `.so` shows zero `retro_*` exports (working cores show 4).
3. Frontend never compiled → CI link command omits `platform/libretro/libretro.o`.
4. Local `-j4` build includes it → environment difference (CC, ccache, clone), not the makefile.
5. Root cause left unresolved; prime suspect CI ccache; recorded as a deferred, rewind-unrelated issue.
