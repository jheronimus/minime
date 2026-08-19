# Minime TODO

## UI

- [ ] MinUI: swap pak defaults to the ecosystem cores — SFC.pak→snes9x, MD.pak→genesis_plus_gx, NGP/NGPC.pak→mednafen_ngp, GBA.pak→mgba (+ rename MGBA.pak to a gpsp fallback pak)
- [ ] MinUI: add DC/N64/PSP paks once minarch grows GL support (blocked on frontend GL work)
- [ ] muOS: add a ppsspp Pickles coredef (`retro/coredef/`) and the fbneo/arcade assign; consider `mednafen_supergrafx` + `mednafen_lynx` coredefs
- [ ] Debug Wi-Fi, BT and Power PAKs in MinUI, make sure everything works well
- [ ] Add boxart support and explore scraper integration (Allium native scraper)
- [ ] Write a MinUI-native frontend to PortMaster (depends on boxart support for screenshots)
- [ ] Reimplement the multi-version ROM feature in MinUI
- [ ] Allium: display proper console names for MinUI-style Roms folders (Option 1, deferred)
  - [THEORY] `ConsoleMapper::get_console_by_dir` (`crates/allium-launcher/src/consoles.rs`) is exact-match only, so a MinUI-named folder like `Game Boy (GB)` displays the raw folder name instead of the console name. Teach it to also match `(ABBREV)` like `get_console` already does.
- [ ] Allium: adopt MinUI's append/merge `wifi.cfg` convention so saving from either UI does not clobber other networks

## Saturn (YabaSanshiro libretro port)

- [ ] Frontend GL support (GLSM/hardware contexts in minarch/Allium) to run the core's GL renderer. The software (Titan) path draws no visible video in this core (verified on-device with a real BIOS: opaque-black frames) — see [ADR 0005](adr/0005-retroarch-cores.md). This is the main blocker for playable Saturn; also unlocks GL/Vulkan for other cores.
- [ ] Multi-disc support: implement `retro_disk_control_callback` so minarch's disc-swap menu works for multi-disc games (e.g. Panzer Dragoon Saga). Needs a glue hook to reinit the CD core on `replace_image_index` ([ADR 0005](adr/0005-retroarch-cores.md)).

## Kernel & Performance

- [ ] Calibrate Dynamic Memory Channel (DMC) Devfreq scaling
  - [THEORY] Lower polling intervals to 50ms/100ms and adjust up/down thresholds to boost RAM throughput under heavy load.

## Power Management & Suspend

- [ ] Re-implement charger-triggered boot handling ([ADR 0012](adr/0012-power-and-thermal.md))
  - [THEORY] Plugging in the charger while off auto-powers-on the device (rk817/RK809 treat AC insertion as power-on). The RK817 PMIC exposes an `ON_SOURCE` register (0xF5, `RK817_ON_SOURCE_REG`; `OFF_SOURCE` 0xF6) that records why the PMIC powered on. A small kernel patch (rk8xx-core.c / rk808.c) could expose it, or U-Boot's `ROCKCHIP_RK8XX_DISABLE_BOOT_ON_POWERON` option could power off at the bootloader level.
- [ ] Implement Fake Suspend & Quick Resume across platforms (RK3566, RK3326, H700)
  - [THEORY] Offline non-boot CPU cores (or throttle CPU0 to 120MHz powersave), mute audio, disable LEDs, turn off Wi-Fi/audio rails, save emulator state, and start auto-shutdown timer.
- [ ] Allium idle auto-sleep should mimic MinUI: suspend first, then auto-shutdown
  - [THEORY] Allium's idle timeout (`alliumd.rs` → `handle_quit()`) currently powers off directly. MinUI (`api.c` `PWR_fauxSleep` → `PWR_waitForWake`) blanks screen/suspends first, and only powers off after ~2 min in sleep when not charging.
- [ ] Qualify real kernel suspend and DTS regulator sleep states (RK3566, RK3326)
- [ ] Analyze and optimize idle power consumption (power domains, runtime-PM, unused rails)

## Display, Audio & Input

- [ ] Comprehensive input mapping & hotkeys across all Minime devices in MinUI and Allium ([ADR 0013](adr/0013-input.md))
  - [THEORY] Configure MinUI (`platform.c` / `minarch`) and Allium (`input.rs` / `alliumd`) to handle input mappings across all form factors:
    - **6-button layout (RG ARC-D / ARC-S)**: Pass `key_c=306` and `key_z=309` alongside A/B/X/Y to `RETRO_DEVICE_ID_JOYPAD_C` and `RETRO_DEVICE_ID_JOYPAD_Z` for Genesis/MD and 6-button arcade cores.
    - **Single/dual-stick & vertical layouts**: Support single-stick vertical devices (RG351V with dedicated `F` key), dual-stick devices (RG35XX-H, RG353 family, RG503, RG351P/M/MP), and stickless devices (RG28XX, RG34XX, RG35XX Plus/SP).
    - **Unified hotkey convention**: Menu button as primary default (`key_menu != na`), fallback to Select on devices lacking a function key.
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)

## Board Infrastructure & System

- [ ] H700 device auto-detection: first-boot probe (MIPI display ID, SARADC sticks, Wi-Fi, lid) + device-selector fallback
- [ ] Compile patched DTB → decompile in CI and compare geometry/keycodes/names/refresh to the traits files
- [ ] Add MTP support
- [ ] Add dual SD card support

## Completed

- [x] Add `input_stick_device_name` trait and multi-evdev joystick polling to Allium and MinUI ([docs/traits/TRAITS.md](traits/TRAITS.md))
- [x] Lightweight C reference reader implementation ([docs/traits/traits.c](traits/traits.c) and `traits.h`)
- [x] Modular RetroArch core builders and configs in `packages/cores/*/core.ini` ([ADR 0005](adr/0005-retroarch-cores.md))
- [x] Ship panel firmware blobs for all H700 panel variants (`packages/components/boards/h700/firmware/`)
- [x] Support and verify switching between Alpine and Buildroot target OSes using `update.sh` ([ADR 0004](adr/0004-updates.md))
- [x] Fix Buildroot Bluetooth service startup: dynamically resolve `bluetoothd` across `/usr/libexec/bluetooth` and `/usr/lib/bluetooth` in `init.d/bluetooth`
- [x] Eliminate bootsplash flicker during switch_root: `--persist` flag preserves DRM scanout framebuffer across initramfs handoff ([ADR 0007](adr/0007-boot.md))
- [x] Review and trim init scripts: start wireless services (`wpa_supplicant`, `bluetoothd`) on demand with user gates
- [x] Optimize Wi-Fi connection speed: non-blocking OpenRC service with early boot parallelization, fast polling, and preserved PSK/SAE hashes
- [x] Bundle static `fsck.fat` in initramfs to check and repair the FAT partition before mounting ([ADR 0009](adr/0009-storage.md))
- [x] Review the remote tool for quality and live diagnostic features ([ADR 0006](adr/0006-diagnostics.md))
- [x] Review fork vs upstream delta for MinUI and Allium; trim excess code ([ADR 0008](adr/0008-ui.md))
- [x] Enable `CONFIG_ENERGY_MODEL=y` in the shared kernel fragment ([ADR 0012](adr/0012-power-and-thermal.md))
- [x] Performance tuning in Alpine with musl and aggressive compiler flags ([ADR 0003](adr/0003-compile-flags.md))
- [x] Default Allium `auto_sleep_when_charging` to `false` so idle timer does not power off while charging
- [x] Mitigate musl UI build cache misses by caching Allium cargo `target/` dirs keyed on `Cargo.lock`
- [x] Shared RetroArch cores between MinUI, Allium, and muOS via `packages/cores/` ([ADR 0005](adr/0005-retroarch-cores.md))
- [x] Unify Roms folder naming to a single MinUI-canonical scheme (`roms/mappings`) resolved by all UIs
- [x] Port Wi-Fi / Bluetooth / Power menus and rewind to MinUI, isolated within platform port ([ADR 0008](adr/0008-ui.md))
- [x] Optimize kernel memory management: COMPACTION, MGLRU, TEO, schedutil; VM sysctls applied via shared OpenRC service
- [x] Fix dead DTB auto-detect path in `boot.cmd`: load `.minime/devices/${device}` with `.minime/dtb` fallback
- [x] RG353M support end-to-end: rgxx3 U-Boot patches applied; traits match runtime compatible `anbernic,rg353p`
- [x] CPU thermal stability + qualification ([ADR 0012](adr/0012-power-and-thermal.md))
- [x] Comprehensive traits audit and validation ([docs/traits/TRAITS.md](traits/TRAITS.md))
- [x] Optimize U-Boot boot speed
- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot ([ADR 0001](adr/0001-musl+glibc.md))
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566
- [x] Fix power button on RG35xxSP not waking the device from sleep
- [x] `dotclean` OpenRC service clears Mac metadata files (`._*`, `.DS_Store`)
- [x] Device hostname announcement via mdnsd (`minime.local`, [ADR 0011](adr/0011-networking.md))
- [x] OTA upload / reboot-wait timeout — detached on-device `update.sh` ([ADR 0004](adr/0004-updates.md))
- [x] RK3326 bringup in CI matrix and target Makefiles
- [x] Integrate mainline Rockchip power/charger drivers and thermal framework ([ADR 0012](adr/0012-power-and-thermal.md))
- [x] Unified DRM bootsplash and display fallback modules ([ADR 0007](adr/0007-boot.md))
