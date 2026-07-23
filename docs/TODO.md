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

## Power Management & Suspend

- [ ] Implement Fake Suspend & Quick Resume across platforms (RK3566, RK3326, H700)
  - [THEORY] Offline non-boot CPU cores (or throttle CPU0 to 120MHz powersave), mute audio, disable LEDs, turn off Wi-Fi/audio rails, save emulator state, and start auto-shutdown timer.
- [ ] Qualify real kernel suspend and DTS regulator sleep states (RK3566, RK3326)
- [ ] Calibrate voltage-based battery gauge with PMIC percentage fallback
- [ ] Enhance LED support (green status LED, charging/battery level indicators, low-battery threshold disable)
- [ ] Fix power button handling
- [ ] Analyze and optimize idle power consumption (power domains, runtime-PM, unused rails)

## Display, Audio & Input

- [ ] Implement driver/DTS level screen rotation instead of per-application handling
- [ ] Fix display refresh timing (60 Hz) and oversharpening via kernel/DTS overlays
- [ ] Implement HDMI output switching
- [ ] Support low-latency Bluetooth audio (aptX and low-latency codecs)
- [ ] Add RG Arc D D-pad / left-stick swap toggle

## Board Infrastructure & System

- [ ] Implement a firstboot device-selector to assist hardware auto-detection ([spec](file:///Users/ilembitov/Projects/minime/docs/spec/firstboot-device-selector.md))
  - [THEORY] Support headless/non-functional screen selection using D-pad up/down inputs, rumble haptics, fast reboot cycles (~2s), and `BTN_A` confirmation once display lights up.
- [ ] Implement U-Boot SPL dual DRAM training fallback for H700 (LPDDR4 -> LPDDR3)
  - [THEORY] Modify `dram_sunxi_h616.c` in U-Boot SPL to attempt LPDDR4 training first and fallback to LPDDR3 timing if training fails, enabling a single U-Boot binary across all H700 RAM variants.
- [ ] Implement init script to clear Mac metadata files (`._*`, `.DS_Store`)
- [ ] Review and trim init scripts; start wireless services (`wpa_supplicant`, `bluetoothd`) on demand
- [ ] Optimize U-Boot boot speed
- [ ] Optimize Wi-Fi connection speed

## Completed

- [x] Reorganize board defconfigs and shared package base between Alpine and Buildroot
- [x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566 via DTS overlays/bootloader options
