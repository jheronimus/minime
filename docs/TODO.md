# Minime TODO

## Kernel & Performance

- [ ] Integrate mainline Rockchip power/charger drivers and enable Energy Model on RK3566
  - [THEORY] Enable `rockchip-pm-domains`, `rk3568-pmu-io-voltage-domain`, and `rk817-charger`; unblocks kernel `CONFIG_THERMAL_OF` and `CONFIG_ENERGY_MODEL` (Panfrost DRM graphics is already active on Alpine).
- [ ] Optimize kernel memory management and schedulers
  - [THEORY] Enable EAS, MGLRU, TEO, schedutil, memory compaction; set swappiness=30, vm.watermark_scale_factor=150, vm.page-cluster=0 ([reference gist](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7)).
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

- [ ] Verify RG DS dual-display traits on hardware: `gpu_device`/`gpu_device2` fb-node ordering, `screen2_backlight_path`, `audio_mic` (DTB wires a microphone; confirm evdev/ALSA surfaces it)
- [ ] Implement driver/DTS level screen rotation instead of per-application handling
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)

## Board Infrastructure & System

- [x] Comprehensive audit of traits system to expose all hardware controls needed for UIs
  - [x] Sectioned schema + layered cascade (`platform.ini` → `parent=` chain → device) per ADR 0012
  - [x] Standardize HDMI state paths via DRM connector (`gpu_hdmi_state_path`), ALSA audio routing helpers
  - [x] Expose power supply and battery status paths (`power_battery_sysfs`, `power_charger_online_path`)
  - [x] Expose LED sysfs control paths (`power_led_path`, charging indicators)
  - [x] Expose input traits and hardware mode toggles (RG ARC touch, d-pad/left-stick swap)
  - [x] Cross-referenced every trait against mainline DTS + Rocknix sources (clone review): keycodes, touch devices (ARC goodix gt927, RG353 hynitron cst340), audio cards/mixers, eMMC topology, HDMI wiring, GPU OPPs, thermal zones
  - [x] Add DTB↔traits cross-reference to `check-traits.sh` (every shipped DTB has a traits file and vice-versa; U-Boot FDT-fixup compatibles allowed)
  - [x] `gpu_hdmi_connector` = stable connector id (e.g. `HDMI-A-1`); `cardN` prefix resolved at init by traits.c/traits.rs (DRM minor index is first-come-first-serve, not static)
  - [ ] Compile patched DTB → decompile in CI and compare geometry/keycodes/names/refresh to the traits files (deeper variant of the cross-reference; needs the kernel build env)
  - [ ] Verify RG DS fb node ordering on real hardware (top-primary ⇒ `gpu_device=/dev/fb1`)
  - [x] Rumble: `input_rumble_device_name` input-FF model (pwm-vibrator) — RK3566 + H700 40XX/CubeXX; verify PWM on hardware
  - [x] RG353P/M/V touch: `CONFIG_TOUCHSCREEN_HYNITRON_CSTXXX` enabled in `tiny-rk3566.config` (both targets)
  - [x] ARC-D/S HDMI: already wired via the `rgxx3.dtsi` include (hdmi-con, &hdmi, &hdmi_sound, vp0→HDMI0) — traits set `gpu_hdmi_connector=HDMI-A-1`; no kernel change needed
  - [ ] Revisit parser design: generic KV-store parser (loop over file into a `key→value` map) + thin typed accessor layer, instead of the hardcoded schema table in traits.c/traits.rs. Trade-off deferred: pure KV loses consumer type-safety/typo detection and missing-vs-zero distinction; schema table is the maintenance surface for renames but surfaces drift loudly. Unknown-key tolerance is already required (shared file carries OS-only keys like `gpu_driver`).
  - [ ] Verify exact H700 mixer control on-device: trait now `Line Out Playback Volume` (old `Line Out` was a routing label, not a control); confirm `amixer` on the SP

- [ ] Fix dead DTB auto-detect path in `boot.cmd`: `device` is resolved from `device.cfg`/`fdtfile` but the DTB load hardcodes `.minime/dtb`
  - [THEORY] Either load `.minime/devices/${device}` when set, or drop the resolution entirely; RK3326 `first-boot-probe.sh` currently writes `device.cfg` that nothing consumes.
- [ ] RK3326 bringup (make `rk3326` a supported board in `minime/targets/*/Makefile` + CI matrix)
- [ ] Add RG353M support end-to-end (U-Boot rgxx3 FDT fixup + traits already added in `rg353m.ini`)

- [ ] Implement a firstboot device-selector to assist hardware auto-detection ([spec](file:///Users/ilembitov/Projects/minime/docs/spec/firstboot-device-selector.md))
  - [THEORY] Support headless/non-functional screen selection using D-pad up/down inputs, rumble haptics, fast reboot cycles (~2s), and `BTN_A` confirmation once display lights up.
- [ ] Implement U-Boot SPL dual DRAM training fallback for H700 (LPDDR4 -> LPDDR3)
  - [THEORY] Modify `dram_sunxi_h616.c` in U-Boot SPL to attempt LPDDR4 training first and fallback to LPDDR3 timing if training fails, enabling a single U-Boot binary across all H700 RAM variants.
- [ ] Implement init script to clear Mac metadata files (`._*`, `.DS_Store`)
- [ ] Review and trim init scripts; start wireless services (`wpa_supplicant`, `bluetoothd`) on demand
- [ ] Research and implement a way for devices to announce their hostname on the network so `just update` could work without a hardcoded `target_ip`
  - [THEORY] e.g. mDNS/`avahi` publishing, or a hostname-based address; would let `just update`/`just check-version`/`just remote` resolve the device without `deploy.cfg`.
- [ ] Investigate why OTA uploads take too long (just update times out at the reboot-wait step even though delivery succeeds)
  - [THEORY] FTP upload of the OTA archive and/or the post-upload reboot-wait could be slow; measure upload throughput and extraction time to find the bottleneck.
- [ ] Optimize U-Boot boot speed
- [ ] Optimize Wi-Fi connection speed

## Completed

- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566 via DTS overlays/bootloader options
- [x] Fix power button on RG35xxSP not waking the device up from sleep
- [x] Update the MinUI `README.txt` shipped on the card
