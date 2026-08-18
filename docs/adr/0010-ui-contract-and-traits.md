# ADR 0010: UI Decoupling, Contract Manifest & Hardware Traits Architecture

## Status
Accepted

## Context
Minime is designed to be strictly UI-agnostic. Unlike monolithic firmware distributions (e.g. Rocknix, MuOS, Knulli), Minime makes zero assumptions about which frontend UI runs on top of it. Low-level hardware platform glue (kernel, Mali GPU drivers, audio routing, input events, hardware traits detection) is isolated completely from frontend user interfaces (MinUI, Allium, or any future UI port).

Previously:
- OS init scripts contained hardcoded paths, UI display names, and explicit process lists for teardown.
- Distro build recipes manufactured custom entrypoint wrappers (`launch.sh`) or generated `ui.env` manifests on the fly.
- Distro image staging created redundant or placeholder user directories (`Roms`, `Bios`, `Saves`, `.userdata`).

## Decision

### Core Contract Boundary
Minime OS has zero internal knowledge of how any UI works. Minime reads `.minime/ui.env` provided by the UI payload, and UIs read hardware traits from `.minime/traits` provided by Minime — that is the complete contract boundary. Minime build scripts and init services must never mutate UI binaries, reorganize UI internal directories, or interpret UI internal logic.

### 1. Hardware Traits Architecture
Hardware platform capabilities are abstracted via immutable `.ini` manifests bundled into the rootfs at build time under `/usr/share/minime/traits/`:
- `platform.ini`: Defines SoC and platform traits (e.g. `sound_card`, `video_device`, `key_*` mappings, `backlight_path`).
- `devices/*.ini`: Defines device-specific traits matched against `/proc/device-tree/model` and `compatible`.

On boot, `init.d/traits` merges `platform.ini` and the matching device manifest into `/mnt/sdcard/.minime/traits`. Core scripts (`ui`, `wifi`) query traits via key lookup functions (`get_trait <key>`). UIs target `minime` directly by reading `/mnt/sdcard/.minime/traits`.

minarch (the emulator host) is not device-tagged: screen dims/rotation reach it via `GFX_init()` from traits, and device clocks/governor resolve in the platform layer. The upstream `DEVICE` envar / `default-<tag>.cfg` per-device config mechanism is unused and was removed from `minarch.c`; paks carry only per-system preferences.

### 2. UI Payload & Archive Extraction Contract
- UIs build and package their release archives (`.zip`) in their own repositories.
- UI release zips must be structured to extract directly onto the SD card root (`/mnt/sdcard/`) without requiring custom subfolder reorganization.
- Minime package build scripts (`alpine/aports/<ui>` and `buildroot/external/package/<ui>`) only fetch and extract the UI release zip flat into the SD staging directory (`$(BINARIES_DIR)/ui/`). Minime build recipes must **never** manufacture wrapper scripts (`launch.sh`), move internal directories, or generate `ui.env` manifests.

### 3. Active UI Manifest Contract (`.minime/ui.env`)
The active UI manifest lives at `/mnt/sdcard/.minime/ui.env`. It is owned and provided 100% by the UI payload archive.

#### Schema
```sh
UI_NAME="<Frontend Display Name>"
UI_BIN="<Absolute path to primary UI executable or entrypoint script on /mnt/sdcard>"
UI_STOP_CMD="<Command or script path for native graceful UI teardown>"
UI_PROCESSES="<Space-separated list of process names for stop cleanup>"
```

#### Example (`.minime/ui.env`)
```sh
UI_NAME="MinUI"
UI_BIN="/mnt/sdcard/.system/minime/paks/MinUI.pak/launch.sh"
UI_STOP_CMD="killall -TERM minui.elf minarch.elf keymon.elf"
UI_PROCESSES="minui.elf minarch.elf keymon.elf clock.elf minput.elf syncsettings.elf say.elf"
```

### 4. Service Lifecycle (`init.d/ui`)
The OS `ui` init script is a clean, UI-agnostic contract executor:
- **Environment & Library Paths**: `ui.sh` does **not** manage `LD_LIBRARY_PATH` or set UI environment variables. Relaunch loops, environment setups, and library loading are 100% internal to the UI payload (managed by RPATH or the UI's own entrypoint script pointed to by `UI_BIN`).
- **Start**: Reads `/mnt/sdcard/.minime/ui.env`. If missing or if `UI_BIN` is non-executable, logs `No UI binary found` to `/mnt/sdcard/boot.log` and exits cleanly. Otherwise, launches `UI_BIN` via `start-stop-daemon`.
- **Stop**: Reads `UI_STOP_CMD` from `ui.env` and executes it for graceful UI teardown. Sends `SIGTERM` to `/tmp/ui.pid` group, then `UI_PROCESSES` cleanup. OS init never hardcodes launcher names.
- **IPC / Shutdown**: UI handles power off / reboot directly. `ui.sh` does not interpret UI IPC files (e.g. `/tmp/next`, `/tmp/poweroff`).

### 5. SD Card Directory Ownership
- Minime OS only creates `/mnt/sdcard/.minime/` (system images, kernel, device tree blobs, traits, hardware configs).
- Minime OS does **not** create media directories (`Roms/`, `Bios/`, `Saves/`) or vestigial storage folders (`.userdata/`). User directories are owned by the UI payload or created on first boot by the UI.

## Rationale
- **Portability & Hot-Swapping**: UIs can be ported or hot-swapped by dropping their files on the SD card and updating `/mnt/sdcard/.minime/ui.env`.
