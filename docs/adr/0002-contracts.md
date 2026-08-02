# ADR 0002: UI Decoupling, Contract Manifest & Hardware Traits Architecture

## Status
Accepted

## Context
Minime is designed to be strictly UI-agnostic. Unlike monolithic firmware distributions (e.g. Rocknix, MuOS, Knulli), Minime makes zero assumptions about which frontend UI runs on top of it. Low-level hardware platform glue (kernel, Mali GPU drivers, audio routing, input events, hardware traits detection) is isolated completely from frontend user interfaces (MinUI, Allium, or any future UI port).

Previously:
- OS init scripts contained hardcoded paths, UI display names, and explicit process lists (`killall minui minarch keymon... alliumd...`) for teardown.
- Distro build recipes (`APKBUILD` / `.mk`) manufactured custom entrypoint wrappers (`launch.sh`) or generated `ui.env` manifests on the fly.
- Distro image staging logic created redundant or placeholder user directories (`Roms`, `Bios`, `Saves`, `.userdata`).

## Decision

### Core Contract Boundary
Minime OS has zero internal knowledge of how any UI works. Minime reads `.minime/ui.env` provided by the UI payload, and UIs read hardware traits from `.minime/traits` provided by Minime — that is the complete contract boundary. Minime build scripts and init services must never mutate UI binaries, reorganize UI internal directories, or interpret UI-specific internal logic.

### 1. Hardware Traits Architecture
Hardware platform capabilities are abstracted via immutable `.ini` manifests bundled into the rootfs at build time under `/usr/share/minime/traits/`:
- `platform.ini`: Defines SoC and platform traits (e.g. `sound_card`, `video_device`, `key_*` mappings, `backlight_path`).
- `devices/*.ini`: Defines device-specific traits matched against `/proc/device-tree/model` and `compatible`.

On boot, `traits.sh` merges `platform.ini` and the matching device manifest into `/mnt/sdcard/.minime/traits`. Core scripts (`ui`, `wifi`) query traits via key lookup functions (`get_trait <key>`). UIs target `minime` directly by reading `/mnt/sdcard/.minime/traits`.

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
UI_PROCESSES="<Space-separated list of process names for stop cleanup>"
```

#### Example (`.minime/ui.env`)
```sh
UI_NAME="MinUI"
UI_BIN="/mnt/sdcard/.system/minime/paks/MinUI.pak/launch.sh"
UI_PROCESSES="minui.elf minarch.elf keymon.elf clock.elf minput.elf syncsettings.elf say.elf"
```

### 4. Service Lifecycle (`init.d/ui`)
The OS `ui` init script is a clean, UI-agnostic contract executor:
- **Environment & Library Paths**: `ui.sh` does **not** manage `LD_LIBRARY_PATH` or set UI environment variables. Relaunch loops, environment setups, and library loading are 100% internal to the UI payload (managed by RPATH or the UI's own entrypoint script pointed to by `UI_BIN`).
- **Start**: Reads `/mnt/sdcard/.minime/ui.env`. If missing or if `UI_BIN` is non-executable, logs `No UI binary found` to `/mnt/sdcard/boot.log` and exits cleanly. Otherwise, launches `UI_BIN` via `start-stop-daemon`.
- **Stop**: Sends `SIGTERM` to `/tmp/ui.pid` process group. If `UI_PROCESSES` is specified in `ui.env`, terminates those processes via `killall`, waits 0.5s, and sends `SIGKILL` (`killall -9`) for clean teardown.
- **IPC / Shutdown**: UI applications handle power off / reboot directly (calling `poweroff` or `reboot`). `ui.sh` does not interpret UI-specific IPC files (e.g. `/tmp/next`, `/tmp/poweroff`).

### 5. SD Card Directory Ownership
- Minime OS only creates `/mnt/sdcard/.minime/` (containing system images, kernel, device tree blobs, traits, and hardware configs).
- Minime OS does **not** create media directories (`Roms/`, `Bios/`, `Saves/`) or vestigial storage folders (`.userdata/`). All user directories are owned by the UI payload or created on first boot by the UI.

## Rationale
- **Zero Coupling**: OS firmware scripts (`ui`, `traits.sh`) and build recipes remain 100% free of UI-specific package names, paths, and entrypoint wrappers.
- **Portability & Hot-Swapping**: Third-party UIs can be ported or hot-swapped simply by dropping their files on the SD card and updating `/mnt/sdcard/.minime/ui.env`.
