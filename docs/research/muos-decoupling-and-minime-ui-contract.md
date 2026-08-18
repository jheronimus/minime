# MuOS Decoupling & Minime UI Contract — Research

> Status: research-phase analysis. The **decided** architecture is [ADR 0028](../adr/0028-muos-frontend-port.md): upstream `MustardOS/frontend` + `MustardOS/internal` submodules, no forks, all Minime code as patches/overlay under `minime/ui/muos/`. This note records the upstream disassembly that informed that decision.

## Upstream Architecture

`MustardOS/internal` supplies OS-level infrastructure: sysinit/udev/dbus/bluetooth services (`script/init/`), per-device hardware INIs (`device/`), OS daemons and utilities (`script/system/`, `bin/`), and the runtime payload (`share/` — themes, fonts, info, assign; `script/` — the POSIX scripts `verify.h` hashes at boot). `MustardOS/frontend` contains the C applications (LVGL 9, PlutoSVG): binaries `muxfrontend`, `mubattery`, `mucredits`, `mufbset`, `muhotkey`, `mulog`, `mulookup`, `murgb`, `musplash`, `muwarn`, `muxcharge`, `muxmessage`, `muremap`; shared `stage/libmustage.so`; sub-project `retro/muxretro` (embedded libretro host).

## Minime Replacement

- Minime's OpenRC init, `device.sh`, ALSA/Mali drivers, and `init.d/traits` replace `internal`'s OS glue (`script/init/`, `script/system/`, `device/`, `bin/`).
- Only `internal/share/` (themes/fonts/info) and `internal/script/` are staged into the payload by `mkui.sh`; the rest is Minime-specific (`launch.sh` + iwd wifi scripts) and lives in `minime/ui/muos/overlay/`.
- `MustardOS/asset` (marketing collateral) and `theme` (3.5 GB theme-manager catalog; the default theme ships in `internal/share/theme/MustardOS`) are not submoduled.
- Minime uses **iwd**, not wpa_supplicant; the frontend's wifi bridge (`muxshare.c` iw/iwctl) is an irreducible patch.

## Payload Layout

| Component | Provided By | Location |
| :--- | :--- | :--- |
| Linux kernel, DTB, GPU, audio, network | Minime OS | RootFS |
| UI init service | Minime OS | `/etc/init.d/ui` → `.minime/ui.env` |
| Hardware traits | Minime OS | `/mnt/sdcard/.minime/traits` |
| muOS binaries | frontend build | `.muos/bin/` |
| muOS share/script | internal submodule | `.muos/share/`, `.muos/script/` |
| Launcher + wifi scripts | Minime overlay | `.muos/launch.sh`, `.muos/script/` |
| RetroArch cores | Minime cores build | `.muos/emulator/retroarch/cores/` |

Payload root: `/mnt/sdcard/.muos/` (hidden dot-directory); `/run/muos/storage` symlinks to `/mnt/sdcard/MUOS`. `ui.env` contract: `UI_NAME="muOS"`, `UI_BIN="/mnt/sdcard/.muos/launch.sh"`, `UI_PROCESSES="muxfrontend mubattery muhotkey mulog"`.

## Key Technical Facts

- Paths in `common/options.h` (`OPT_PATH`, `MAIN_ROM_DIR`, …) are wrapped in `#ifndef` guards so the two Minime values can be applied by patch without touching core logic.
- `cfg_dir_scan`/`load_device` read `device/config/*` key-files where **filename = key, content = value** (not JSON); `launch.sh` derives them from the traits.
- `muxfrontend` expects `launch.sh` to be its parent (PDEATHSIG contract) — `launch.sh` owns the lifecycle loop and companions (`muhotkey`, `mubattery`).
- SDL mappings need a per-name CRC: the gamepad and stick share identical bus/vendor/product/version; the evdev GUID is `bus + crc16(name) + VID + PID + version` (see ADR 0028).

## References

- [ADR 0028](../adr/0028-muos-frontend-port.md) — decided architecture
- [ADR 0010](../adr/0010-ui-contract-and-traits.md) — UI contract & traits
- [MustardOS/internal](https://github.com/MustardOS/internal) — `script/`, `share/`, `device/`
- [MustardOS/frontend](https://github.com/MustardOS/frontend) — `Makefile`, `common/options.h`, `module/muxfrontend.c`