# Minime TODO

## CI


- [ ] Try switching between Alpine and Buildroot using update.sh

## UI

- [ ] Debug Wi-Fi, BT and Power PAKs in MinUI, make sure everything works well
- [ ] Add boxart support and maybe a scraper PAK (Allium is implementing its own scraper these days)?
- [ ] Write a MinUI-native frontend to PortMaster (depends on the boxart support to display screenshots)
- [ ] Reimplement the multi-version ROM feature in MinUI
- [ ] Allium: display proper console names for MinUI-style Roms folders (Option 1, deferred)
  - [THEORY] `ConsoleMapper::get_console_by_dir` (`crates/allium-launcher/src/consoles.rs`) is exact-match only, so a MinUI-named folder like `Game Boy (GB)` displays the raw folder name instead of the console name. Teach it to also match `(ABBREV)` like `get_console` already does. This is a shared-crate change (AGENTS.md minimal-intrusion exception), so it's deferred. **Accepted for now (Option 2): keep raw folder names as the display name.**
- [ ] Allium: adopt MinUI's append/merge `wifi.cfg` convention so saving from either UI does not clobber other networks
  - [THEORY] Allium's minime `update_wpa_supplicant_conf()` uses `File::create` (overwrite); MinUI's `WIFI_connect` appends only when the SSID is new. Deferred until Allium adopts the same append convention.

## Saturn (YabaSanshiro libretro port)

- [ ] Frontend GL support (GLSM/hardware contexts in minarch/Allium) to run the core's GL renderer. The software (Titan) path draws no visible video in this core (verified on-device with a real BIOS: opaque-black frames) — see [ADR 0023](adr/0023-yabasanshiro-libretro-port.md). This is the main blocker for playable Saturn; also unlocks GL/Vulkan for other cores.
- [ ] Multi-disc support: implement `retro_disk_control_callback` so minarch's disc-swap menu works for multi-disc games (e.g. Panzer Dragoon Saga). Needs a glue hook to reinit the CD core on `replace_image_index`. Deferred ([ADR 0023](adr/0023-yabasanshiro-libretro-port.md)).
- [ ] Buildroot two-core split: the GL-linked core does not build on Buildroot (libmali ships no desktop `libGL`); ship a software-only variant there ([ADR 0023](adr/0023-yabasanshiro-libretro-port.md)).

## Kernel & Performance

- [ ] Calibrate Dynamic Memory Channel (DMC) Devfreq scaling
  - [THEORY] Lower polling intervals to 50ms/100ms and adjust up/down thresholds to boost RAM throughput under heavy load.


## Power Management & Suspend

- [ ] Re-implement charger-triggered boot handling (ADR 0020 superseded; script removed)
  - [THEORY] Plugging in the charger while off auto-powers-on the device (rk817/RK809 treat AC insertion as power-on). We need appliance behavior: power off unless the user deliberately pressed power. The old `init.d/charger` grace-window approach was removed because it cannot detect the user's power press: the press that *boots* the device happens before evdev/pwrkey is up, so the grace-window evdev poll never sees it.
  - [KEY FINDING] The RK817 PMIC exposes an `ON_SOURCE` register (0xF5, `RK817_ON_SOURCE_REG`; `OFF_SOURCE` 0xF6) that records why the PMIC powered on (PWRON key vs. USB/VDC plug-in vs. RTC alarm). This is the MuOS boot-source signal that ADR 0020 claimed was unavailable on RK3566 — it is readable, just not exported via sysfs. A small kernel patch (rk8xx-core.c / rk808.c) could expose it, or U-Boot's `ROCKCHIP_RK8XX_DISABLE_BOOT_ON_POWERON` option could power off at the bootloader level before the OS even starts. Until then, plugging in while off leaves the device running (overnight drain) and OTA reboots while charging lose the `.software_reboot` bypass.
- [ ] Implement Fake Suspend & Quick Resume across platforms (RK3566, RK3326, H700)
  - [THEORY] Offline non-boot CPU cores (or throttle CPU0 to 120MHz powersave), mute audio, disable LEDs, turn off Wi-Fi/audio rails, save emulator state, and start auto-shutdown timer.
- [ ] Allium idle auto-sleep should mimic MinUI: suspend first, then auto-shutdown
  - [THEORY] Allium's idle timeout (`alliumd.rs` → `handle_quit()`) currently **powers off directly** — it never suspends first. MinUI (`api.c` `PWR_fauxSleep` → `PWR_waitForWake`) instead blanks the screen / suspends, and only auto-powers-off after ~2 min in sleep when **not** charging. Mirror that on Minime: on idle timeout call `handle_suspend()`, then if still idle & not charging, `handle_quit()`.
- [ ] Qualify real kernel suspend and DTS regulator sleep states (RK3566, RK3326)

- [ ] Analyze and optimize idle power consumption (power domains, runtime-PM, unused rails)

## Display, Audio & Input

- [ ] On-device verify display orientation per device with `just shell "remote screenshot --raw"` ([ADR 0027](adr/0027-display-rotation.md)): confirm RG28XX (270) / RG40XX-V (90) / RG351V (90) directions and correct any that are 180° off. Confirm the newly-shipped H700 panel firmware blobs bring the rg28xx/rg34xx/rg40xx/rgcubexx panels up upright.
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)

## Board Infrastructure & System

- [ ] Inspect Rocknix per-platform/device quirks for adoptable fixes (RK3566, RK3326, H700)
  - [THEORY] Boot-time scripts under `hardware/quirks/platforms/{RK3566,RK3326,H700}` and `hardware/quirks/devices/*` (per-DT-model override dirs) cover far more than power/thermal: thermal trips, governor/DVFS paths, turbo/boost, GPU floors, suspend/fake-suspend hooks, fan/LED/battery handling, audio latency/volume, input modifiers, UI service selection, WiFi/BT. Quirks are executed every boot by `/usr/bin/autostart` — platform (SoC) dir first, then device dir, then global `autostart/common`; they persist state via `/storage/.config/profile.d/NNN-*` files and are wired into suspend/resume via `sleep.d/{pre,post}/*`. Not all installed quirks run (device dir is installed for all models but only the matching DT-model subdir executes; some guard on settings/DT nodes). Sources: [RK3566 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3566), [RK3326 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3326), [H700 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/H700), [device quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/devices).
- [ ] H700 device auto-detection: first-boot probe (MIPI display ID, SARADC sticks, Wi-Fi, lid) + device-selector fallback; ship all panel firmware ([ADR 0012](adr/0012-h700-device-detection.md))
- [ ] Review and trim init scripts; start wireless services (`wpa_supplicant`, `bluetoothd`) on demand
- [ ] Optimize Wi-Fi connection speed
- [ ] Compile patched DTB → decompile in CI and compare geometry/keycodes/names/refresh to the traits files (deeper variant of the cross-reference; needs the kernel build env)
- [ ] Revisit parser design: generic KV-store parser (loop over file into a `key→value` map) + thin typed accessor layer, instead of the hardcoded schema table in traits.c/traits.rs. Trade-off deferred: pure KV loses consumer type-safety/typo detection and missing-vs-zero distinction; schema table is the maintenance surface for renames but surfaces drift loudly. Unknown-key tolerance is already required (shared file carries OS-only keys like `gpu_driver`).
- [ ] Review the traits system again
  - [THEORY] Traits hand-copy values that already live in the DTS (freqs, keycodes, thermal trips, GPU OPPs) — every repetition is a drift risk. Explore generating trait values from the compiled DTB at build time (DTS as single source of truth) so hand-authored copies cannot silently diverge; hand-author only true device facts (identity, geometry) that the DTS does not expose.
- [ ] Add MTP support
- [ ] Add dual SD card support

## Completed

- [x] Bundle static `fsck.fat` in initramfs to check and repair the FAT partition before mounting
- [x] Review the remote tool done by Gemini for quality
- [x] Review the fork vs upstream delta for MinUI and Allium; trim excess code
- [x] Enable `CONFIG_ENERGY_MODEL=y` in the shared kernel fragment (ADR 0018)
- [x] Investigate how performance can be improved in Alpine with musl
- [x] Default Allium `auto_sleep_when_charging` to `false` so the idle timer does not power off while charging
- [x] Investigate why musl UI build is 2x slower: slow `ubuntu-24.04-arm` runner on cache-miss; mitigated by caching Allium cargo `target/` dirs keyed on `Cargo.lock`
- [x] Shared RetroArch cores between MinUI and Allium via `build-cores` CI job and `cores-<libc>` artifact
- [x] Unify Roms folder naming to a single MinUI-canonical scheme (`roms/mappings`) resolved by both UIs
- [x] Port Wi-Fi / Bluetooth / Power menus and rewind to MinUI, isolated (ADR 0025)
- [x] Optimize kernel memory management: COMPACTION, MGLRU, TEO, schedutil; VM sysctls applied via shared OpenRC sysctl service
- [x] Fix dead DTB auto-detect path in `boot.cmd`: load `.minime/devices/${device}` with `.minime/dtb` fallback
- [x] RG353M support end-to-end: rgxx3 U-Boot patches applied; traits match runtime compatible `anbernic,rg353p`
- [x] CPU thermal stability + qualification (ADR 0018)
- [x] Comprehensive traits audit (ADR 0011)
- [x] Optimize U-Boot boot speed
- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566
- [x] Fix power button on RG35xxSP not waking the device from sleep
- [x] Update the MinUI `README.txt` shipped on the card
- [x] `dotclean` OpenRC service clears Mac metadata files (`._*`, `.DS_Store`)
- [x] Device hostname announcement via mdnsd (`minime.local`, ADR 0017)
- [x] OTA upload / reboot-wait timeout — detached on-device `update.sh` (ADR 0003)
- [x] RK3326 bringup in CI matrix and both `minime/targets/*/Makefile` boards
- [x] Integrate mainline Rockchip power/charger drivers (PM domains, IO domain, RK817 charger) and thermal framework
- [x] Ship panel firmware blobs for all H700 panel variants (rg34xx-sp, rg35xx-sp-v2, rg40xx-v2)
- [x] Unified DRM bootsplash (plane rotation, dumb buffers) and Allium DRM display module with fallback
