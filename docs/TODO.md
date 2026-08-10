# Minime TODO

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

- [ ] Implement Fake Suspend & Quick Resume across platforms (RK3566, RK3326, H700)
  - [THEORY] Offline non-boot CPU cores (or throttle CPU0 to 120MHz powersave), mute audio, disable LEDs, turn off Wi-Fi/audio rails, save emulator state, and start auto-shutdown timer.
- [ ] Qualify real kernel suspend and DTS regulator sleep states (RK3566, RK3326)
- [ ] Calibrate voltage-based battery gauge with PMIC percentage fallback
- [ ] Enhance LED support (green status LED, charging/battery level indicators, low-battery threshold disable)
- [ ] Analyze and optimize idle power consumption (power domains, runtime-PM, unused rails)

## Display, Audio & Input

- [ ] Implement driver/DTS level screen rotation instead of per-application handling
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)

## Board Infrastructure & System

- [ ] Port the Wi-Fi menu from the MinUI fork's `IMPORT` branch (`jheronimus/MinUI`), isolated
  - [THEORY] `origin/IMPORT` carries a proper Wi-Fi settings menu that the fork's `main` has since refactored away: `src/settings/wifi.c` (menu rows: toggle / network list grouped by connected / known / open, with hints), `src/ui/keyboard.c`+`keyboard.h` (on-screen keyboard: SHIFT/SPACE/DEL/DONE), `src/platform/minime/wireless.c`+`wireless.h` (iwd backend: refresh/setEnabled/connect/disconnect/forget), `src/settings/jobs.*` (async job queue: wifi toggle/connect/disconnect/forget), plus `UI_DIALOG_openWifiPassphrase` and the settings `snapshot`/`item`/`hint` plumbing. Import the wifi menu + keyboard + wireless backend **minimally and self-contained** — preserve app functionality (on-screen keyboard, network list, connect/forget) while making the smallest possible change to the current MinUI codebase. Keep all new code in the `workspace/minime/` port dir or a single settings module; avoid pulling in the unrelated IMPORT refactor.
  - [COMPAT] Figure out `wifi.cfg` compatibility with Allium. Minime's `wifi` OpenRC service reads `SSID=`/`Passphrase=` pairs from `.minime/config/wifi.cfg` and writes one `.psk` profile per pair, so the format supports **multiple networks**. Allium's minime `update_wpa_supplicant_conf()` currently does `File::create` (overwrite) — saving from Allium clobbers any other networks, and vice-versa. Decide: (a) a shared multi-network append/merge convention both UIs use, or (b) a single-network source of truth (e.g. last-write-wins) with explicit documentation, or (c) a dedicated per-UI config that a shared loader merges. Confirm how `load_wifi_cfg_profiles` + `rc-service wifi reload` behave when multiple networks are present and how MinUI should let the user pick/order them.

- [ ] Inspect Rocknix per-platform/device quirks for adoptable fixes (RK3566, RK3326, H700)
  - [THEORY] Boot-time scripts under `hardware/quirks/platforms/{RK3566,RK3326,H700}` and `hardware/quirks/devices/*` (per-DT-model override dirs) cover far more than power/thermal: thermal trips, governor/DVFS paths, turbo/boost, GPU floors, suspend/fake-suspend hooks, fan/LED/battery handling, audio latency/volume, input modifiers, UI service selection, WiFi/BT. Quirks are executed every boot by `/usr/bin/autostart` — platform (SoC) dir first, then device dir, then global `autostart/common`; they persist state via `/storage/.config/profile.d/NNN-*` files and are wired into suspend/resume via `sleep.d/{pre,post}/*`. Not all installed quirks run (device dir is installed for all models but only the matching DT-model subdir executes; some guard on settings/DT nodes). Sources: [RK3566 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3566), [RK3326 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3326), [H700 quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/platforms/H700), [device quirks](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/hardware/quirks/devices).

- [ ] Fix dead DTB auto-detect path in `boot.cmd`: `device` is resolved from `device.cfg`/`fdtfile` but the DTB load hardcodes `.minime/dtb`
  - [THEORY] Either load `.minime/devices/${device}` when set, or drop the resolution entirely; RK3326 `first-boot-probe.sh` currently writes `device.cfg` that nothing consumes.
- [ ] RK3326 bringup (make `rk3326` a supported board in `minime/targets/*/Makefile` + CI matrix)
- [ ] Add RG353M support end-to-end (U-Boot rgxx3 FDT fixup + traits already added in `rg353m.ini`)

- [ ] Implement a firstboot device-selector to assist hardware auto-detection ([spec](research/firstboot-device-selector.md))
  - [THEORY] Support headless/non-functional screen selection using D-pad up/down inputs, rumble haptics, fast reboot cycles (~2s), and `BTN_A` confirmation once display lights up.
- [ ] Implement U-Boot SPL dual DRAM training fallback for H700 (LPDDR4 -> LPDDR3)
  - [THEORY] Modify `dram_sunxi_h616.c` in U-Boot SPL to attempt LPDDR4 training first and fallback to LPDDR3 timing if training fails, enabling a single U-Boot binary across all H700 RAM variants.
- [ ] Implement init script to clear Mac metadata files (`._*`, `.DS_Store`)
- [ ] Review and trim init scripts; start wireless services (`wpa_supplicant`, `bluetoothd`) on demand
- [ ] Research and implement a way for devices to announce their hostname on the network so `just update` could work without a hardcoded `target_ip`
  - [THEORY] e.g. mDNS/`avahi` publishing, or a hostname-based address; would let `just update`/`just check-version`/`just remote` resolve the device without `deploy.cfg`.
- [ ] Investigate why OTA uploads take too long (just update times out at the reboot-wait step even though delivery succeeds)
  - [THEORY] FTP upload of the OTA archive and/or the post-upload reboot-wait could be slow; measure upload throughput and extraction time to find the bottleneck.
- [ ] Optimize Wi-Fi connection speed

- [ ] Compile patched DTB → decompile in CI and compare geometry/keycodes/names/refresh to the traits files (deeper variant of the cross-reference; needs the kernel build env)
- [ ] Verify RG DS fb node ordering on real hardware (top-primary ⇒ `gpu_device=/dev/fb1`)
- [ ] Revisit parser design: generic KV-store parser (loop over file into a `key→value` map) + thin typed accessor layer, instead of the hardcoded schema table in traits.c/traits.rs. Trade-off deferred: pure KV loses consumer type-safety/typo detection and missing-vs-zero distinction; schema table is the maintenance surface for renames but surfaces drift loudly. Unknown-key tolerance is already required (shared file carries OS-only keys like `gpu_driver`).
- [ ] Review the traits system again
  - [THEORY] Traits hand-copy values that already live in the DTS (freqs, keycodes, thermal trips, GPU OPPs) — every repetition is a drift risk. Explore generating trait values from the compiled DTB at build time (DTS as single source of truth) so hand-authored copies cannot silently diverge; hand-author only true device facts (identity, geometry) that the DTS does not expose.

## Completed

- [x] CPU thermal stability policy + qualification procedure ([ADR 0014](adr/0014-cpu-performance-and-thermal-policy.md))
  - [x] RK3566 DTS thermal trips raised to 83/88 °C CPU, 80/88 °C GPU passive (`0017-arm64-dts-rockchip-rk356x-update-thermal-trips.patch`); TSADC 95 °C hardware shutdown untouched
  - [x] Default `cpu_clock_performance` 1800 → 1608 MHz in RK3566 traits; 1800 MHz now requires opt-in undervolt
  - [x] Thermal monitoring merged into the `logger` service (thresholds derived from `trip_point_*` sysfs, throttle telemetry, `syslogd -l` keeps it off the framebuffer); standalone `thermal-watchdog` service removed
  - [x] `stress-ng` + `memtester` behind a `TEST_PACKAGES=1` build-time opt-in (Alpine `world-test` fragment, Buildroot `test.config`)
- [x] Comprehensive audit of traits system to expose all hardware controls needed for UIs
  - [x] Sectioned schema + layered cascade (`platform.ini` → `parent=` chain → device) per ADR 0012
  - [x] Standardize HDMI state paths via DRM connector (`gpu_hdmi_state_path`), ALSA audio routing helpers
  - [x] Expose power supply and battery status paths (`power_battery_sysfs`, `power_charger_online_path`)
  - [x] Expose LED sysfs control paths (`power_led_path`, charging indicators)
  - [x] Expose input traits and hardware mode toggles (RG ARC touch, d-pad/left-stick swap)
  - [x] Cross-referenced every trait against mainline DTS + Rocknix sources (clone review): keycodes, touch devices (ARC goodix gt927, RG353 hynitron cst340), audio cards/mixers, eMMC topology, HDMI wiring, GPU OPPs, thermal zones
  - [x] Add DTB↔traits cross-reference to `check-traits.sh` (every shipped DTB has a traits file and vice-versa; U-Boot FDT-fixup compatibles allowed)
  - [x] `gpu_hdmi_connector` = stable connector id (e.g. `HDMI-A-1`); `cardN` prefix resolved at init by traits.c/traits.rs (DRM minor index is first-come-first-serve, not static)
  - [x] Rumble: `input_rumble_device_name` input-FF model (pwm-vibrator) — RK3566 + H700 40XX/CubeXX; verify PWM on hardware
  - [x] RG353P/M/V touch: `CONFIG_TOUCHSCREEN_HYNITRON_CSTXXX` enabled in `tiny-rk3566.config` (both targets)
  - [x] ARC-D/S HDMI: already wired via the `rgxx3.dtsi` include (hdmi-con, &hdmi, &hdmi_sound, vp0→HDMI0) — traits set `gpu_hdmi_connector=HDMI-A-1`; no kernel change needed
  - [x] Verify exact H700 mixer control on-device: `audio_mixer=Line Out` is the correct simple-mixer control (`amixer sset 'Line Out' <pct>% unmute` works, volume + mute toggle). The H700/H616 codec ALSO exposes a raw numid control (`Line Out Playback Volume`, numid=2, INTEGER 0-31) that is NOT a simple control — `sset` can't see it and `cset '<name>'` fails; only `cset numid=2 <val>` works. The numid control must NOT be used as `audio_mixer`. (Earlier traits used `Line Out Playback Volume`/`Master Playback Volume` — corrected to `Line Out` on all boards.)
- [x] Optimize U-Boot boot speed
- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566 via DTS overlays/bootloader options
- [x] Fix power button on RG35xxSP not waking the device up from sleep
- [x] Update the MinUI `README.txt` shipped on the card
