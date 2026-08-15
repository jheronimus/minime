# MuOS Decoupling & Minime Target/UI Contract Feasibility Research

## Executive Summary

This research evaluates the technical feasibility of decoupling **muOS** ([MustardOS](https://github.com/MustardOS)) from its native Buildroot OS foundations and porting its user interface frontend to run on top of **Minime**, fully conforming to [ADR 0010: UI Decoupling, Contract Manifest & Hardware Traits Architecture](../adr/0010-ui-contract-and-traits.md).

### Core Principles & Architecture Strategy
1. **Surgical Isolation & Low Code Churn**: Upstream `MustardOS/frontend` is actively developed. All changes must be strictly isolated (via conditional macro overrides, thin shims, and environment fallbacks) to ensure effortless upstream rebase and tracking.
2. **Complete Bypassing of `MustardOS/internal`**: Minime's hardware traits system (`/mnt/sdcard/.minime/traits`) and UI contract (`.minime/ui.env`) perform everything `MustardOS/internal` does at the OS level. `MustardOS/internal` is ~90% redundant OS firmware glue (sysinit, udev, dbus, bluetooth, power/storage scripts, per-device INIs). Therefore, **we can completely eliminate `MustardOS/internal` from our porting effort**, maintaining only a fork of `MustardOS/frontend` paired with a lightweight set of launcher assets.

---

## Upstream Architecture & Disassembly

### 1. `MustardOS/internal` (Redundant / Replaced by Minime OS)
The `internal` repository ([MustardOS/internal](https://github.com/MustardOS/internal)) supplies OS-level infrastructure:
- **Sysinit & OS Services**: `script/init/` (`S10udev.sh`, `S30dbus.sh`, `S75bluetooth.sh`, `S80pipewire.sh`, `S99muos.sh`).
- **Per-Device Hardware Directories**: `device/` (`rg35xx-h`, `rg40xx-h`, `tui-brick`, etc.) holding static INIs for screen, audio, and input.
- **OS Daemons & Utilities**: `script/system/` (battery, swap, storage, USB gadget).

**Minime Replacement**: Minime's OpenRC init system, `device.sh`, native ALSA/Mali drivers, and `init.d/traits` render `MustardOS/internal` obsolete. Only the minimal launcher scripts (`frontend.sh`, `launch.sh`) and stock UI assets (`share/`) are retained and bundled into the UI payload.

### 2. `MustardOS/frontend` (Primary Target for Porting)
The `frontend` repository ([MustardOS/frontend](https://github.com/MustardOS/frontend)) contains the C applications compiled against LVGL 9, PlutoSVG, and custom rendering backends.

- **Hardcoded Path Macros**:
  - `common/options.h`: Hardcoded paths (`OPT_PATH "/opt/muos/"`, `RUN_PATH "/run/muos/"`, `CONF_CONFIG_PATH OPT_PATH "config/"`, `OPT_SHARE_PATH OPT_PATH "share/"`).
- **Modules & Output Binaries**:
  - Binaries: `muxfrontend`, `mubattery`, `mucredits`, `mufbset`, `muhotkey`, `mulog`, `mulookup`, `murgb`, `musplash`, `muwarn`, `muxcharge`, `muxmessage`, `muremap`.
  - Shared Library: `stage/libmustage.so` (GLES/KMS OSD overlay).
  - Sub-project: `retro/muxretro` (embedded libretro host).

---

## OS vs. Payload Separation Matrix

| Component / Layer | Provided By | Location | Description |
| :--- | :--- | :--- | :--- |
| **Linux Kernel & DTB** | Minime OS | `/boot/` | Hardware-specific kernel and device tree blobs |
| **GPU Drivers & Display** | Minime OS | RootFS (`/usr/lib`) | Mali GPU binaries (`libmali`), DRM/KMS graphics drivers |
| **Audio & Network** | Minime OS | RootFS | ALSA, BlueZ, `wpa_supplicant`, OpenRC init services |
| **UI Init Service** | Minime OS | `/etc/init.d/ui` | UI-agnostic OpenRC launcher executing `.minime/ui.env` |
| **Hardware Traits** | Minime OS | `/mnt/sdcard/.minime/traits` | Hardware capabilities manifest output by `init.d/traits` |
| **muOS C Binaries** | muOS Payload | `/mnt/sdcard/MUOS/bin/` | Compiled `MustardOS/frontend` binaries (`muxfrontend`, `mubattery`, `muhotkey`, `mulog`, `libmustage.so`) |
| **muOS Launcher Scripts** | muOS Payload | `/mnt/sdcard/MUOS/script/` | Lightweight orchestration scripts (`frontend.sh`, `launch.sh`, `quit.sh`, `func.sh`) |
| **muOS UI Assets** | muOS Payload | `/mnt/sdcard/MUOS/share/` | Fonts, themes, language bundles, gamecontrollerdb |
| **Active UI Manifest** | muOS Payload | `/mnt/sdcard/.minime/ui.env` | ADR 0010 contract file describing muOS entrypoint |

---

## Implementing the Minime UI Contract (ADR 0010 Compliance)

### 1. Active UI Manifest (`.minime/ui.env`)
The muOS payload archive bundles `.minime/ui.env` at the root of the zip archive:

```sh
UI_NAME="muOS"
UI_BIN="/mnt/sdcard/MUOS/launch.sh"
UI_PROCESSES="muxfrontend mubattery muhotkey mulog murgb musplash muxmessage"
```

### 2. Payload Entrypoint Wrapper (`MUOS/launch.sh`)
The entrypoint script initializes the environment and launches the frontend loop:

```sh
#!/bin/sh
# /mnt/sdcard/MUOS/launch.sh

export MUOS_ROOT="/mnt/sdcard/MUOS"
export LD_LIBRARY_PATH="$MUOS_ROOT/bin/lib:$MUOS_ROOT/bin:$LD_LIBRARY_PATH"

# Run muOS frontend event loop
exec "$MUOS_ROOT/script/mux/frontend.sh"
```

### 3. Hardware Traits Integration (`/mnt/sdcard/.minime/traits`)
Instead of reading per-board configs from `MustardOS/internal`'s `device/` folder, muOS scripts parse Minime's hardware traits:

```sh
GET_TRAIT() {
    KEY="$1"
    TRAITS_FILE="/mnt/sdcard/.minime/traits"
    if [ -f "$TRAITS_FILE" ]; then
        grep "^${KEY}=" "$TRAITS_FILE" | cut -d'=' -f2-
    fi
}
```

- `sound_card` -> ALSA card index for audio mixer reset.
- `video_device` -> DRM/KMS node (`/dev/dri/card0`).
- `key_*` -> Input event button mappings for `muhotkey` and `gptokeyb`.

### 4. Power & Lifecycle Management
- **Start**: `/etc/init.d/ui` reads `.minime/ui.env` and executes `/mnt/sdcard/MUOS/launch.sh` via `start-stop-daemon`.
- **Shutdown / Reboot**: `script/mux/quit.sh` calls `poweroff` or `reboot` directly (fully ADR 0010 compliant).
- **Stop / Teardown**: Minime OS sends `SIGTERM` to `launch.sh` process group, followed by `killall -9 UI_PROCESSES`.

---

## Surgical Implementation Strategy & Minimizing Upstream Churn

To keep `MustardOS/frontend` easily updateable from upstream:

1. **Header-Level Path Abstraction (`options.h`)**:
   Wrap path definitions in `#ifndef` guards so they can be overridden via `CFLAGS` or a build config header without editing core source files:
   ```c
   #ifndef OPT_PATH
   #define OPT_PATH "/mnt/sdcard/MUOS/"
   #endif
   ```
2. **Minimal Shims**:
   Keep all Minime trait parsing logic in dedicated shim files (`minime_traits.h` / `minime_traits.c`) or inside `func.sh`, rather than scattering changes across LVGL UI files (`ui_*.c`).
3. **Single Repository Focus (`MustardOS/frontend`)**:
   Do **not** maintain a fork of `MustardOS/internal`. Store the required shell scripts (`frontend.sh`, `launch.sh`, `func.sh`) and stock assets (`share/`) directly inside the `muos-frontend` packaging repo alongside `frontend`.

---

## Refactoring Workflow

1. **Fork `MustardOS/frontend`**:
   - Maintain a single fork focused exclusively on UI compilation.
2. **Add Path & Trait Overrides**:
   - Add `#ifndef OPT_PATH` wrappers in `options.h`.
   - Add trait reader shim in `common/board.c` reading `/mnt/sdcard/.minime/traits`.
3. **CI Packaging Pipeline**:
   - GitHub Actions workflow cross-compiles `frontend` C binaries for ARM64.
   - Assembles `MUOS/` payload (`bin/`, minimal `script/`, `share/`, and `.minime/ui.env`).
   - Produces `muos-minime.zip`.
4. **Minime Packaging Integration**:
   - Add package recipe (`alpine/aports/muos` and `buildroot/external/package/muos`) to fetch `muos-minime.zip` flat into `$(BINARIES_DIR)/ui/` for image creation.

---

## Primary Sources & References

- [ADR 0010: UI Decoupling, Contract Manifest & Hardware Traits Architecture](../adr/0010-ui-contract-and-traits.md)
- [MustardOS/internal Repository](https://github.com/MustardOS/internal) (`script/init/S99muos.sh`, `script/mux/frontend.sh`, `script/var/func.sh`)
- [MustardOS/frontend Repository](https://github.com/MustardOS/frontend) (`Makefile`, `common/options.h`, `common/config.c`, `module/muxfrontend.c`)
