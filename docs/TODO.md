# Minime TODO

## CI
- [x] Investigate why musl build of UI now takes 2x the time of glibc
  - [DONE] Not a container error — both images pull/build fine. The gap appears only on UI-cache-miss runs: musl runs natively on the slower `ubuntu-24.04-arm` runner while glibc cross-compiles on `ubuntu-latest` (x86-64), and on a miss the full ~300-crate cargo tree + RetroArch recompile on the slow runner. Mitigation: cache the Allium cargo `target/` dirs (workspace + dufs/collie) keyed on their `Cargo.lock` files in `build-ui` (`allium-target-{libc}-*`).
- [ ] Try switching between Alpine and Buildroot using update.sh

## UI
- [x] Streamline the RetroArch cores between MinUI and Allium
  - [DONE] Shared cores built once by the new `build-cores` CI job (matrix musl/glibc) from `minime/build/cores/manifest` (17 recipes: the 13 MinUI cores + handy + mednafen_wswan + yabasanshiro + drastic) with `buildcores.sh`; artifact `cores-<libc>` is consumed by both UIs (`build.yml`, `mkui.sh`). The MinUI submodule no longer builds cores (`cores:` target now injects the flat artifact into `SYSTEM/minime/cores`); all emulator paks moved to base SYSTEM (+ new LYNX/WS/SAT/NDS paks). Allium injects the `.so` files into `RetroArch/.retroarch/cores/`. `update-cores.yml` bumps `autobump=1` pins (mgba + WIP drastic/yabasanshiro stay pinned).
  - [DONE] Q6 Roms naming: `roms/mappings` is now a single 2-column MinUI-canonical scheme (no Allium dual naming); `roms/install.sh`, `update.sh`, and both `post-build.sh` lost the rename machinery; MinUI skeleton Roms folders mirror the canonical names and resolve on Allium (added SMS/SAT/NGPC/P8/MGBA/SUPA patterns + race core for NGP/NGPC).
- [ ] Allium: display proper console names for MinUI-style Roms folders (Option 1, deferred)
  - [THEORY] `ConsoleMapper::get_console_by_dir` (`crates/allium-launcher/src/consoles.rs`) is exact-match only, so a MinUI-named folder like `Game Boy (GB)` displays the raw folder name instead of the console name. Teach it to also match `(ABBREV)` like `get_console` already does. This is a shared-crate change (AGENTS.md minimal-intrusion exception), so it's deferred. **Accepted for now (Option 2): keep raw folder names as the display name.**
- [ ] Port the Wi-Fi menu from the MinUI fork's `IMPORT` branch (`jheronimus/MinUI`), isolated
  - [THEORY] `origin/IMPORT` carries a proper Wi-Fi settings menu that the fork's `main` has since refactored away: `src/settings/wifi.c` (menu rows: toggle / network list grouped by connected / known / open, with hints), `src/ui/keyboard.c`+`keyboard.h` (on-screen keyboard: SHIFT/SPACE/DEL/DONE), `src/platform/minime/wireless.c`+`wireless.h` (iwd backend: refresh/setEnabled/connect/disconnect/forget), `src/settings/jobs.*` (async job queue: wifi toggle/connect/disconnect/forget), plus `UI_DIALOG_openWifiPassphrase` and the settings `snapshot`/`item`/`hint` plumbing. Import the wifi menu + keyboard + wireless backend **minimally and self-contained** — preserve app functionality (on-screen keyboard, network list, connect/forget) while making the smallest possible change to the current MinUI codebase. Keep all new code in the `workspace/minime/` port dir or a single settings module; avoid pulling in the unrelated IMPORT refactor.
  - [COMPAT] Figure out `wifi.cfg` compatibility with Allium. Minime's `wifi` OpenRC service reads `SSID=`/`Passphrase=` pairs from `.minime/config/wifi.cfg` and writes one `.psk` profile per pair, so the format supports **multiple networks**. Allium's minime `update_wpa_supplicant_conf()` currently does `File::create` (overwrite) — saving from Allium clobbers any other networks, and vice-versa. Decide: (a) a shared multi-network append/merge convention both UIs use, or (b) a single-network source of truth (e.g. last-write-wins) with explicit documentation, or (c) a dedicated per-UI config that a shared loader merges. Confirm how `load_wifi_cfg_profiles` + `rc-service wifi reload` behave when multiple networks are present and how MinUI should let the user pick/order them.


## Kernel & Performance

- [ ] Integrate mainline Rockchip power/charger drivers (`rockchip-pm-domains`, `rk3568-pmu-io-voltage-domain`, `rk817-charger`) to unblock `CONFIG_THERMAL_OF` on all boards
  - [x] `CONFIG_ENERGY_MODEL=y` enabled in the shared kernel fragment (ADR 0014)
- [ ] Optimize kernel memory management and schedulers
  - [x] `CONFIG_COMPACTION=y` enabled (CMA GPU heap pressure, ADR 0014)
  - [ ] EAS (`CONFIG_SCHED_ENERGY`) deferred: no populated energy model on RK3566 (ADR 0014). Remaining: MGLRU, TEO, schedutil; set swappiness=30, vm.watermark_scale_factor=150, vm.page-cluster=0 ([reference gist](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7)).
- [ ] Calibrate Dynamic Memory Channel (DMC) Devfreq scaling
  - [THEORY] Lower polling intervals to 50ms/100ms and adjust up/down thresholds to boost RAM throughput under heavy load.
- [ ] Expose selectable performance profiles (Max Performance, Balanced, Power Save)
  - [THEORY] Atomic profile application for governor, frequency bounds, and core limits via key combinations or minimal UI.
- [ ] Investigate how performance can be improved in Alpine with musl
  - [THEORY] jemmalloc/mimalloc3?

## Power Management & Suspend

- [ ] Re-implement charger-triggered boot handling (ADR 0020 superseded; script removed)
  - [THEORY] Plugging in the charger while off auto-powers-on the device (rk817/RK809 treat AC insertion as power-on). We need appliance behavior: power off unless the user deliberately pressed power. The old `init.d/charger` grace-window approach was removed because it cannot detect the user's power press: the press that *boots* the device happens before evdev/pwrkey is up, so the grace-window evdev poll never sees it.
  - [KEY FINDING] The RK817 PMIC exposes an `ON_SOURCE` register (0xF5, `RK817_ON_SOURCE_REG`; `OFF_SOURCE` 0xF6) that records why the PMIC powered on (PWRON key vs. USB/VDC plug-in vs. RTC alarm). This is the MuOS boot-source signal that ADR 0020 claimed was unavailable on RK3566 — it is readable, just not exported via sysfs. A small kernel patch (rk8xx-core.c / rk808.c) could expose it, or U-Boot's `ROCKCHIP_RK8XX_DISABLE_BOOT_ON_POWERON` option could power off at the bootloader level before the OS even starts. Until then, plugging in while off leaves the device running (overnight drain) and OTA reboots while charging lose the `.software_reboot` bypass.
- [ ] Implement Fake Suspend & Quick Resume across platforms (RK3566, RK3326, H700)
  - [THEORY] Offline non-boot CPU cores (or throttle CPU0 to 120MHz powersave), mute audio, disable LEDs, turn off Wi-Fi/audio rails, save emulator state, and start auto-shutdown timer.
- [ ] Allium idle auto-sleep should mimic MinUI: suspend first, then auto-shutdown
  - [DONE] Default `auto_sleep_when_charging` to `false` (Allium power.rs) so the 5-min idle timer no longer powers off while charging.
  - [THEORY] Allium's idle timeout (`alliumd.rs` → `handle_quit()`) currently **powers off directly** — it never suspends first. MinUI (`api.c` `PWR_fauxSleep` → `PWR_waitForWake`) instead blanks the screen / suspends, and only auto-powers-off after ~2 min in sleep when **not** charging. Mirror that on Minime: on idle timeout call `handle_suspend()`, then if still idle & not charging, `handle_quit()`.
- [ ] Qualify real kernel suspend and DTS regulator sleep states (RK3566, RK3326)
- [ ] Calibrate voltage-based battery gauge with PMIC percentage fallback
- [ ] Enhance LED support (green status LED, charging/battery level indicators, low-battery threshold disable)
- [ ] Analyze and optimize idle power consumption (power domains, runtime-PM, unused rails)

## Display, Audio & Input

- [ ] Implement driver/DTS level screen rotation instead of per-application handling
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)
- [ ] Implement the bootsplash ([ADR 0019](adr/0019-bootsplash.md)): `MINIME` framebuffer art + looping gradient bar across initramfs/rootfs, volume-key TTY reveal, `ui`-service failure handoff, single-owner boot brightness

## Board Infrastructure & System

- [ ] Inspect Rocknix per-platform/device quirks for adoptable fixes (RK3566, RK3326, H700)
  - [THEORY] Boot-time scripts under `hardware/quirks/platforms/{RK3566,RK3326,H700}` and `hardware/quirks/devices/*` (per-DT-model override dirs) cover far more than power/thermal: thermal trips, governor/DVFS paths, turbo/boost, GPU floors, suspend/fake-suspend hooks, fan/LED/battery handling, audio latency/volume, input modifiers, UI service selection, WiFi/BT. Quirks are executed every boot by `/usr/bin/autostart` — platform (SoC) dir first, then device dir, then global `autostart/common`; they persist state via `/storage/.config/profile.d/NNN-*` files and are wired into suspend/resume via `sleep.d/{pre,post}/*`. Not all installed quirks run (device dir is installed for all models but only the matching DT-model subdir executes; some guard on settings/DT nodes). Sources: [RK3566 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3566), [RK3326 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3326), [H700 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/H700), [device quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/devices).

- [ ] Fix dead DTB auto-detect path in `boot.cmd`: `device` is resolved from `device.cfg`/`fdtfile` but the DTB load hardcodes `.minime/dtb`
  - [THEORY] Either load `.minime/devices/${device}` when set, or drop the resolution entirely; RK3326 `first-boot-probe.sh` currently writes `device.cfg` that nothing consumes.
- [ ] Add RG353M support end-to-end (U-Boot rgxx3 FDT fixup + traits already added in `rg353m.ini`)

- [ ] Implement a firstboot device-selector to assist hardware auto-detection ([spec](research/firstboot-device-selector.md))
  - [THEORY] Support headless/non-functional screen selection using D-pad up/down inputs, rumble haptics, fast reboot cycles (~2s), and `BTN_A` confirmation once display lights up.
- [ ] Implement U-Boot SPL dual DRAM training fallback for H700 (LPDDR4 -> LPDDR3)
  - [THEORY] Modify `dram_sunxi_h616.c` in U-Boot SPL to attempt LPDDR4 training first and fallback to LPDDR3 timing if training fails, enabling a single U-Boot binary across all H700 RAM variants.
- [ ] Review and trim init scripts; start wireless services (`wpa_supplicant`, `bluetoothd`) on demand
- [ ] Optimize Wi-Fi connection speed

- [ ] Compile patched DTB → decompile in CI and compare geometry/keycodes/names/refresh to the traits files (deeper variant of the cross-reference; needs the kernel build env)
- [ ] Revisit parser design: generic KV-store parser (loop over file into a `key→value` map) + thin typed accessor layer, instead of the hardcoded schema table in traits.c/traits.rs. Trade-off deferred: pure KV loses consumer type-safety/typo detection and missing-vs-zero distinction; schema table is the maintenance surface for renames but surfaces drift loudly. Unknown-key tolerance is already required (shared file carries OS-only keys like `gpu_driver`).
- [ ] Review the traits system again
  - [THEORY] Traits hand-copy values that already live in the DTS (freqs, keycodes, thermal trips, GPU OPPs) — every repetition is a drift risk. Explore generating trait values from the compiled DTB at build time (DTS as single source of truth) so hand-authored copies cannot silently diverge; hand-author only true device facts (identity, geometry) that the DTS does not expose.

## Completed

- [x] CPU thermal stability + qualification (ADR 0014): RK3566 trips 83/88 °C CPU, 80/88 °C GPU passive; default perf 1800→1608 MHz; telemetry folded into `logger`; `stress-ng`/`memtester` behind `TEST_PACKAGES=1`
- [x] Comprehensive traits audit (ADR 0012): sectioned schema + cascade; HDMI/battery/LED/input traits; DTB↔traits cross-check in `check-traits.sh`; H700 mixer = `Line Out`
- [x] Optimize U-Boot boot speed
- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566 via DTS overlays/bootloader options
- [x] Fix power button on RG35xxSP not waking the device from sleep
- [x] Update the MinUI `README.txt` shipped on the card
- [x] Implement init script to clear Mac metadata files (`._*`, `.DS_Store`) — `dotclean` OpenRC service runs on boot over every card under `/mnt`
- [x] Device hostname announcement on the network — every device advertises `minime.local` via mdnsd (ADR 0018); `just remote` resolves without a hardcoded `target_ip`
- [x] OTA upload / reboot-wait timeout — resolved by replacing host-push `just update` with the detached on-device `update.sh` (ADR 0017); the reboot-wait problem no longer exists
- [x] RK3326 bringup — supported in the CI matrix and both `minime/targets/*/Makefile` boards
