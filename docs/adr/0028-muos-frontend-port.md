# ADR 0028: muOS Frontend Platform Port

## Context

Minime supports MinUI and Allium as selectable frontends per [ADR 0010](0010-ui-contract-and-traits.md) (UI contract + hardware traits). muOS (MustardOS) is a feature-rich LVGL/SDL2 frontend; adding it gives a third launcher with box art, theme engine, and core assignment on Minime's minimal OS base.

## Decisions

### 1. Repository Structure & Isolation
- **Upstream submodules, no forks**: `packages/ui/muos/frontend` tracks `MustardOS/frontend` (pinned to upstream `main`) and `packages/ui/muos/internal` (shallow, `update=none`) tracks `MustardOS/internal`. All Minime-specific code lives in `packages/ui/muos/`: a 7-file patch series (`patches/`, applied with `git apply --3way` before the container build, then reset away) and the launcher/wifi overlay (`overlay/`), both staged by `mkui.sh`. `MustardOS/asset` (marketing collateral) and `theme` (3.5 GB theme-manager catalog; the default theme ships in `internal/share/theme/MustardOS`) are intentionally not submoduled.
- **Zero shared-C divergence (Option A)**: `common/device.c`, `common/input.c`, `module/muxfrontend.c`, and `common/Makefile` are byte-identical to upstream. The only `options.h` deviations are two `#ifndef` guards (`OPT_PATH=/mnt/sdcard/.muos/`, `MAIN_ROM_DIR="Roms"`); `launch.sh` is the parent `muxfrontend` relies on (upstream PDEATHSIG contract).
- **Bridge, not shim**: `launch.sh` (the only port surface) derives every `device/config/*` key-file from the traits — the files `cfg_dir_scan`/`load_device` read (filename = key, content = value) — synthesizes the SDL `sdl_map` (GUID = bus+`crc16(name)`+VID/PID/version, button indices by ascending evdev keycode rank; the stick `adc-joystick` mapping is appended to the gamecontrollerdb files), symlinks `/run/muos/storage` → `/mnt/sdcard/MUOS`, seeds `config/settings/general/orientation=0` to skip the New User Guide, and runs the frontend lifecycle loop.
- **Kernel dependency**: the input drivers (gpio-keys / adc-joystick / adc-keys) are patched to report the DT node name via `EVIOCGNAME` (`*-input-name-devices-from-dt-node.patch`), so trait device names match SDL/kernel truth.

### 2. Filesystem Layout & UI Contract
- **Payload location**: `/mnt/sdcard/.muos/` (hidden dot-directory on FAT32).
- **Compile-time path**: `#define OPT_PATH "/mnt/sdcard/.muos/"` via `platform/minime/` macro overrides. No OS rootfs symlinks or mounts are required.
- **Runtime tmpfs**: `/mnt/sdcard/.muos/launch.sh` creates ephemeral runtime directories (`/run/muos/`, `/tmp/muos/`) on tmpfs before exec.
- **Contract manifest**: `/mnt/sdcard/.packages/ui.env` specifies:
  ```sh
  UI_NAME="muOS"
  UI_BIN="/mnt/sdcard/.muos/launch.sh"
  UI_PROCESSES="muxfrontend mubattery muhotkey mulog"
  ```
- **OS init**: `/etc/init.d/ui` executes `$UI_BIN` without UI-specific knowledge.

### 3. ROMs & System Assignment
- **ROM directory**: `#define MAIN_ROM_DIR "Roms"` (points exclusively to `/mnt/sdcard/Roms/`).
- **MinUI folder alignment**: System assignment manifests in `share/info/assign/` use MinUI directory names, so the same SD card and `Roms/` structure works across MinUI, Allium, and muOS with zero conversion.

### 4. Background Daemons & Power
- Companion daemons `muhotkey` and `mubattery` run alongside `muxfrontend` from `launch.sh`.
- Hardware sysfs paths (backlight, battery, power key) are queried via Minime traits.

### 5. Dual-Libc CI Parity
- muOS builds for both Alpine (`musl`) and Buildroot (`glibc`) in GitHub Actions using `crash_stub.c` for toolchains without `execinfo.h`.
- Artifacts (`muos-musl-aarch64.tar.zst`, `muos-glibc-aarch64.tar.zst`) are integrated directly into image generation via `packages/image/genassets.sh`.
- The `.muos` payload is assembled by `mkui.sh`: `bin/` from the frontend build; `share/` (themes/fonts/info) and `script/` staged from the `muos/internal` submodule (`init/`, `bin/`, `device/` are not staged — Minime replaces the init flow with `launch.sh` and derives device config from traits); `launch.sh` + iwd wifi scripts from `packages/ui/muos/overlay`; shared cores injected into `emulator/retroarch/cores/`. The submodule checkouts are restored to pristine after staging (nothing is committed to them). UI cache keys hash both submodule HEADs.

## Consequences

- Upstream tracking is clean with zero patch collisions — only the `packages/ui/muos` patch series + overlay diverge, 3way-applied so they tolerate upstream drift.
- No forks to maintain; the fork's delta is fully preserved as patches + overlay.
- Single SD card works across all three frontends; full compliance with the UI contract and traits.
- CI cost: `muos/internal` is `update=none` — recursive checkouts skip it; only the muos build jobs sparse-clone `share/` + `script/` (~730 MB) via `packages/ui/muos-checkout-internal.sh`, so the other 10 jobs download nothing extra.
