# ADR 0002: UI Payload Decoupling & Hardware Traits Architecture

## Status
Accepted

## Context
Minime isolates low-level hardware platform glue (kernel, Mali GPU drivers, audio routing, traits detection) from frontend user interfaces (MinUI, Allium, or custom UI ports).

Previously, `ui.sh` contained hardcoded paths (`/mnt/sdcard/.system/minime/bin/minui`, `/mnt/sdcard/.ui/bin/alliumd`), UI display names (`MinUI`, `Allium`), and explicit process lists (`killall minui minarch keymon... alliumd...`) for teardown. This coupled the OS init layer directly to specific frontend packages.

Additionally, device-specific hardware properties (sound cards, input event devices, keycodes, backlight sysfs paths) were scattered or hardcoded across startup scripts.

## Decision

### 1. Hardware Traits Architecture
Hardware platform capabilities are abstracted via immutable `.ini` manifests bundled into the rootfs at build time under `/usr/share/minime/traits/`:
- `platform.ini`: Defines SoC and platform traits (e.g. `sound_card`, `video_device`, `key_*` mappings, `backlight_path`).
- `devices/*.ini`: Defines device-specific traits matched against `/proc/device-tree/model` and `compatible`.

On boot, `traits.sh` merges `platform.ini` and the matching device manifest into `/mnt/sdcard/.minime/traits`. Core scripts (`ui.sh`, `wifi.sh`) query traits via key lookup functions (`get_trait <key>`).

### 2. UI Payload Decoupling Contract (`ui.env`)
Frontends installed on the SD card must ship a manifest file at `/mnt/sdcard/.minime/ui.env`.

#### Schema
```sh
UI_NAME="<Frontend Display Name>"
UI_BIN="<Absolute path to primary UI executable>"
UI_PROCESSES="<Space-separated list of child/auxiliary process names for stop cleanup>"
```

#### Example (MinUI)
```sh
UI_NAME="MinUI"
UI_BIN="/mnt/sdcard/.system/minime/bin/minui"
UI_PROCESSES="minui minarch keymon clock minput syncsettings say"
```

#### Example (Allium)
```sh
UI_NAME="Allium"
UI_BIN="/mnt/sdcard/.ui/bin/alliumd"
UI_PROCESSES="alliumd allium-launcher allium-menu"
```

### 3. Service Lifecycle (`ui.sh`)
- `ui.sh` knows **nothing** about specific UI names, filesystem layouts, or binary locations.
- **Start**: Reads `/mnt/sdcard/.minime/ui.env`. If missing or if `UI_BIN` is non-executable, logs `No UI binary found` to `/mnt/sdcard/boot.log` and exits cleanly.
- **Stop**: Terminates `/tmp/ui_loop.pid` and its process tree via `pkill -P`. If `$UI_PROCESSES` is set in `ui.env`, terminates those processes via `killall`.

## Rationale
- **Extensibility**: Third-party frontends can be ported to Minime simply by dropping `.minime/ui.env` on the SD card without modifying OS firmware scripts or rebuilding the rootfs (`erofs`).
- **Maintainability**: Hardware glue scripts (`ui.sh`, `traits.sh`) remain lean, deterministic, and free of hardcoded package names.
