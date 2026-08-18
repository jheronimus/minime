# ADR 0028: muOS Frontend Platform Port

## Context

Minime supports MinUI and Allium as selectable frontends, following [ADR 0010](0010-ui-contract-and-traits.md) (UI contract manifest and hardware traits). MustardOS (muOS) is a popular, feature-rich retro gaming frontend based on LVGL and SDL2. Adding muOS as Minime's third frontend gives users a full-featured launcher with box art, theme engine, and core assignment while keeping Minime's minimal, fast OS base.

## Decisions

### 1. Fork Scope & Isolation
- **Frontend fork only**: Fork exclusively `MustardOS/frontend`. The upstream OS layer (`MustardOS/internal`) is 100% bypassed and superseded by Minime's OpenRC init system and hardware traits (`/mnt/sdcard/.minime/traits`).
- **Platform shim (`platform/minime/`)**: Add a self-contained platform directory in the fork with `traits.c`, `traits.h`, and `platform.c`. Upstream UI widgets and modules remain unmodified to make upstream synchronization trivial.

### 2. Filesystem Layout & UI Contract
- **Payload location**: `/mnt/sdcard/.muos/` (hidden dot-directory on FAT32).
- **Compile-time path**: `#define OPT_PATH "/mnt/sdcard/.muos/"` via `platform/minime/` macro overrides. No OS rootfs symlinks or mounts are required.
- **Runtime tmpfs**: `/mnt/sdcard/.muos/launch.sh` creates ephemeral runtime directories (`/run/muos/`, `/tmp/muos/`) on tmpfs before exec.
- **Contract manifest**: `/mnt/sdcard/.minime/ui.env` specifies:
  ```sh
  UI_NAME="muOS"
  UI_BIN="/mnt/sdcard/.muos/launch.sh"
  UI_PROCESSES="muxfrontend mubattery muhotkey mulog"
  ```
- **OS init**: `/etc/init.d/ui` executes `$UI_BIN` without UI-specific knowledge.

### 3. ROMs & System Assignment
- **ROM directory**: `#define MAIN_ROM_DIR "Roms"` (points exclusively to `/mnt/sdcard/Roms/`).
- **MinUI folder alignment**: System assignment manifests in `share/info/assign/` use standard MinUI directory names (`Game Boy (GB)`, `Game Boy Advance (GBA)`, `PlayStation (PS)`).
- **Interoperability**: The same SD card and `Roms/` structure functions identically across MinUI, Allium, and muOS with zero conversion.

### 4. Background Daemons & Power
- Companion daemons `muhotkey` and `mubattery` run alongside `muxfrontend` from `launch.sh`.
- Hardware sysfs paths (backlight, battery, power key) are queried via Minime traits.

### 5. Dual-Libc CI Parity
- muOS builds for both Alpine (`musl`) and Buildroot (`glibc`) in GitHub Actions using `crash_stub.c` for toolchains without `execinfo.h`.
- Artifacts (`muos-musl-aarch64.zip`, `muos-glibc-aarch64.zip`) are integrated directly into image generation via `minime/build/genassets.sh`.

## Consequences

- Upstream muOS tracking is clean with zero patch collisions.
- Single SD card compatibility across all three Minime frontends.
- Full compliance with Minime UI contract and hardware traits architecture.
