**6 out of 50 complete**

[ ] Implement an init script to clear Mac dot files
[ ] Check Dynamic Memory Channel (DMC) Devfreq Calibration (lowering polling intervals to 50ms/100ms and dropping scaling thresholds to force system RAM to full speed under heavy load)
[ ] Optimize kernel schedulers/allocators: enable EAS (Energy-Aware Scheduling), MGLRU (Multi-Gen LRU), TEO, schedutil, memory compaction, reduce swappiness to 30, vm.watermark_scale_factor = 150, vm.page-cluster = 0 (see [this gist](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7)) — note: enabling CONFIG_ENERGY_MODEL + CONFIG_THERMAL_OF hangs `modprobe mali_kbase` (out-of-tree Mali blob driver's devfreq cooling-device registration is incompatible with the mainline energy-model API; em_create() hangs building the power model from the Mali dynamic-coefficient). Rocknix/Knulli use the same thermal configs successfully because they use Panfrost (mainline). Blocked on the Panfrost migration (see "Integrate Panfrost" item).
[ ] Create a BIOS manifest file that contains required BIOS files for the cores and their checksums (needs to be part of the cores package)
[ ] UIs use bezels from the system-wide package, do not ship their own
[ ] Review init scripts, trim down where possible.
[ ] Review board files: check that common/board specific division is still correct. Cascade the defconfigs so there's a shared package base between the devices
[ ] Review kernel patches, drop everything that's been mainlined/not needed anymore/specific to Rocknix or non-Anbernic devices
[ ] Review the new libmali for RK3566 for Vulkan compatibility
[ ] Implement HDMI switching on Minime's side
[ ] Refactor and import Allium UI for Minime
[ ] Refactor and import OnionUI for Minime
[ ] Enable kernel suspend configurations, DTS regulator sleep states, and audio/Wi-Fi power-gating on RK3566/RK3326
[ ] Implement Fake Suspend & Quick Resume (offline cores, powersave governor, mute audio, disable LEDs, auto-shutdown timer, state save/reload) on RK3566/RK3326
[ ] Implement Quick-Save & Auto-Resume (Hibernation) on H700 (capture quicksaves and poweroff on lid close/power press, boot back in < 6s)
[ ] Optimize Fake Suspend on H700 (offline CPU cores 1-3, throttle CPU0 to 120MHz powersave, turn off Wi-Fi/audio rails, auto-shutdown delay)
[ ] Add configurable idle/suspend actions (dim, display off, sleep, auto-mute, disable battery saving when charging) to the minimal UI for all platforms
[ ] Check that maybe we need to rotate the screen at the drivers level or DTS instead of doing this in each program separately
[ ] Check if uboot can be sped up
[ ] Check if wi-fi connect can be done faster
[ ] Analyze and improve the power consumption
[ ] Enhance LED support: fix LED status (green during normal operation), support RGB/mono battery levels/charging indicators, and disable LEDs below a configured threshold.
[ ] Migrate to exFAT and add fsck tools
[ ] Fix power button
[x] Enable CPU/GPU overclock (up to 2.0 GHz) and undervolt support for RK3566 via DTS overlays/bootloader options (include extlinux.conf recovery docs)
[ ] Expose selectable performance profiles (Max Performance, Balanced, Power Save) and thread/TDP control via minimal UI or key combinations
[ ] Integrate Panfrost (Mali-G52) and mainline Rockchip power/charger drivers (rockchip-pm-domains, rk3568-pmu-io-voltage-domain, rk817-charger) — also unblocks CONFIG_ENERGY_MODEL/EAS/thermal-of configs (out-of-tree mali_kbase hangs with those).
[ ] Implement accurate calibrated voltage-based battery gauge with option to fallback to PMIC percentage
[ ] Enable oversharpening and 60 Hz display fixes via kernel or DT overlays
[ ] Support low-latency Bluetooth audio (aptX etc.)
[ ] Evaluate and integrate mainline kernel developments (e.g. kernel 6.x backports, HW video decoding)
[x] Implement a new bootsplash, Gameboy Color style
[x] Review and simplify MinUI code, check for slop
[x] Create device traits file containing device-specific configuration (written after first-boot DTB autodetection, used by UIs to avoid hardcoded configs) and clean up MinUI rg35xxplus code
[x] Make FTP passwordless
[x] Add userspace thermal watchdog (RK3566): polls SoC thermal zones every 2s and throttles CPU/GPU cooling devices at 70/76/82/88C; interim until the Panfrost migration unblocks the in-kernel governor

## RK3566 performance, stability, and battery checklist

[ ] Establish an RG Arc D baseline at stock clocks: record boot time, idle/gameplay power draw, suspend drain, peak temperature, frame-time percentiles, input latency, and memory-pressure behaviour with fixed workloads; use the same checks for every optimisation below.
[ ] Verify MGLRU on RK3566 under load: confirm `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y`, and runtime activation; run one repeatable zram/memory-pressure check and retain MGLRU only if it reduces stalls without increasing failed allocations or emulator regressions.
[ ] Implement atomic RK3566 performance profiles: apply CPU governor/rate limits, CPU/GPU maximum frequencies, and optional core limits as one transaction; restore the prior state after resume or emulator exit and verify the effective sysfs values for Max Performance, Balanced, and Power Save.
[ ] Calibrate RK3566 DMC devfreq: confirm the DFI counters and memory-frequency transitions work, test 50 ms and 100 ms polling plus revised up/down thresholds, then select settings from frame-time and power results rather than forcing maximum RAM frequency globally.
[ ] Complete the RK3566 Panfrost cutover: remove `mali_kbase`, proprietary `libmali`, and Mali-fbdev coupling from the RK3566 image; verify DRM/KMS startup, GLES applications, emulator rendering, suspend/resume, and GPU runtime power management on every supported RK3566 DTB.
[ ] Replace the RK3566 userspace thermal watchdog after Panfrost lands: enable `CONFIG_ENERGY_MODEL` and `CONFIG_THERMAL_OF`, add validated CPU/GPU cooling maps and trip points, run sustained stock/overclock/undervolt thermal tests, and remove `S15thermal-watchdog` only after kernel throttling and critical shutdown both pass.
[ ] Audit RK3566 runtime power domains and regulators: measure GPU, VPU, NPU, USB, audio amplifier, Wi-Fi, and Bluetooth idle states; fix DTS/runtime-PM ownership for blocks that remain powered while unused and confirm each change lowers idle draw without breaking wake or device detection.
[ ] Qualify real suspend on every supported RK3566 device: add regulator sleep states and explicit wake sources, then run 100 suspend/resume cycles with display, audio, controls, storage, Wi-Fi, and Bluetooth checks; record suspend current and block release for any data corruption, failed wake, or rail left enabled.
[ ] Implement reversible RK3566 fake suspend: snapshot governor/frequency/core, display, audio, LED, Wi-Fi, and Bluetooth state before changing it; freeze the emulator, apply the low-power state, honour charging and auto-shutdown settings, then restore the exact snapshot on wake or rollback after any partial failure.
[ ] Calibrate the RK3566 battery gauge per battery/device profile: collect charge and discharge voltage curves under idle and gameplay loads, add filtering and hysteresis, preserve the RK817 percentage fallback, and verify monotonic display values, charging transitions, low-battery warnings, and safe shutdown thresholds.
[ ] Stop unused RK3566 wireless services and hardware: start `bluetoothd`, BlueALSA, and `wpa_supplicant` only when enabled; use rfkill/runtime power management when disabled, enable supported Wi-Fi power saving when idle, and measure idle draw plus reconnect and Bluetooth-audio latency before and after.
[ ] Implement opt-in RK3566 quick-save and auto-resume: request an atomic emulator save state on suspend or orderly shutdown, store enough metadata to validate the ROM/core match, resume once on the next boot, and fall back to the normal UI when the state is missing, stale, corrupt, or unsupported.
[ ] Validate RK3566 display timing per panel: measure the delivered refresh rate and frame cadence on every supported DTB, add panel-specific 60 Hz timing or oversharpening fixes only where the defect is reproduced, and regression-check blanking, brightness, rotation, tearing, and suspend/resume.
[ ] Add an RG Arc D D-pad/left-stick swap: implement the mapping at the narrowest shared input boundary, expose one documented toggle or button chord, persist the selected mode, and verify no stuck keys, duplicate events, added polling loop, or mapping changes on other RK3566 devices.
