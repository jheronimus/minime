# 0012: Minime Traits Schema & Cascade

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-07

---

## Context & Problem Statement

Minime exposes device hardware traits to UIs via a flat `key=value` file at
`/mnt/sdcard/.minime/traits`. Historically the file was a single flat list
with no structure, trait names were inconsistent (`bluetooth_adapter` vs
`wifi_interface`), values drifted from reality (e.g. H700 `power_led_path`,
`rumble_path`, and the extcon HDMI path did not exist on device), and each
device `.ini` duplicated large shared blocks.

This ADR freezes the trait schema: sectioned files, a layered cascade, a
naming convention, and a strict parser contract so UIs (MinUI, Allium, and
future ports) can consume traits identically.

## Decision Drivers

- **UI-Agnostic Contract**: UIs read one flat file and must not re-derive
  device knowledge. Trait values that name a device-tree entity use the DT
  name verbatim; keycodes are numeric evdev codes matching the compiled DTB.
- **No Drift**: `scripts/check-traits.sh` validates the schema statically,
  and the emitted file is generated on the device from the immutable payload,
  so traits cannot silently diverge from the shipped DTBs.
- **Expansive but Grounded**: the schema covers real device features (dual
  display, touch, USB roles, storage topology, GPU clocks, thermal) without
  speculative traits no current hardware uses.

## Decided Architecture

### 1. Layered cascade

Three levels, resolved at boot by `init.d/traits`:

1. `platform.ini` — SoC-wide defaults (screen/backlight, CPU clocks +
   thermal, GPU, audio, input device names, keycodes, power, USB, storage).
2. `devices/<base>.ini` — per-device traits (identity, screen geometry,
   HDMI, touch, rumble, wireless).
3. `devices/<revision>.ini` — panel-revision variants (rev6/v2) that set
   `parent=<base-device>` and only override identity.

`init.d/traits` merges the chain `platform.ini` → rootmost parent → … →
device file, emitting every key. **The last value of a duplicated key wins**
(any trait may be overridden at any lower level). The `parent` key and the
`[match]` section are meta-data and never emitted.

### 2. File sections

Both `platform.ini` and device files use the same section headers. The
generated `/mnt/sdcard/.minime/traits` keeps `key=value` lines only; section
headers are documentation and ignored by parsers.

```
[device]    device_id, device_model

[screen]    screen_width, screen_height, screen_rotation, screen_aspect,
            screen_refresh_rate, screen_backlight_path, screen_backlight_max,
            screen_blank_path,
            screen2_width, screen2_height, screen2_rotation,
            screen2_backlight_path, screen2_blank_path,
            screen2_touch, screen2_touch_device_name

[cpu]       cpu_governor_path, cpu_clock_path,
            cpu_clock_menu, cpu_clock_powersave, cpu_clock_normal,
            cpu_clock_performance,
            cpu_undervolt_supported, cpu_thermal_path

[gpu]       gpu_device, gpu_device2, gpu_hdmi_connector,
            gpu_clock_min, gpu_clock_max

[audio]     audio_card, audio_mixer, audio_jack_device_name, audio_mic

[input]     input_gamepad_device_name, input_power_device_name,
            input_volume_device_name, input_lid_device_name,
            input_rumble_device_name, input_touch, input_touch_device_name,
            key_up, key_down, key_left, key_right,
            key_a, key_b, key_c, key_x, key_y, key_z,
            key_l1, key_r1, key_l2, key_r2, key_l3, key_r3,
            key_start, key_select, key_menu, key_power,
            key_vol_up, key_vol_down,
            input_axis_lx, input_axis_ly, input_axis_rx, input_axis_ry,
            input_axis_min, input_axis_center, input_axis_max,
            input_axis_lx_invert, input_axis_ly_invert,
            input_axis_rx_invert, input_axis_ry_invert

[wireless]  wifi_interface, bluetooth_interface

[power]     power_battery_sysfs, power_charger_online_path, power_led_path

[usb]       usb_otg, usb_host_ports, usb_device_mode, usb_controller_mode

[storage]   storage_sd_node, storage_sd2_node, storage_emmc_node
```

### 3. Naming rules

- Keys are section-prefixed **except** `key_*`, `input_axis_*`,
  `wifi_interface`, and `bluetooth_interface` (their section is obvious and
  the flat file is collision-safe without the prefix).
- Values naming a device-tree entity (input device names, sysfs paths, block
  nodes) use the DT name **verbatim** — e.g. `gpio-keys-gamepad`,
  `/sys/class/leds/green:power/brightness`, `/dev/mmcblk0`.
- Keycodes are numeric evdev codes (e.g. `key_a=305`), matching what the
  kernel reports and what the compiled DTB contains. UIs compare event codes
  directly; no symbol table in either the file or the consumers.
- `na` means "not present / not available" for nullable fields. Absent keys
  are treated as `na`.
- The `gpu_*` section covers display output + GPU: `gpu_device=/dev/fb0`
  today, `gpu_device2` for dual-display (RG DS), `gpu_hdmi_connector` as a
  stable DRM connector identifier (e.g. `HDMI-A-1`), and `gpu_clock_min/max`
  from the SoC OPP table. `gpu_driver` is **not** in the source files: it is
  a build-target value (Alpine injects `gpu_driver=panfrost`, Buildroot
  `gpu_driver=mali_kbase`) appended by each target's `post-build.sh`, so the
  emitted file always matches the shipped GPU driver.

  `gpu_hdmi_connector` intentionally excludes the DRM card number: the
  `cardN` prefix is the DRM primary-minor index, allocated first-come-
  first-serve at probe time, so it is not a stable path. Consumers resolve it
  at init by scanning `/sys/class/drm/card*-<connector>/status` (see
  `docs/research/traits.c` `resolve_hdmi_connector()`).

### 5. Source-of-truth verification

Every trait value was cross-referenced against the mainline DTS/DTSi and
Rocknix sources (cloned, not web-searched) plus on-device checks:

- **Keycodes** match the DTS `linux,code` values (numeric, matching evdev).
- **Touch device names** come from the input driver source:
  `"Goodix Capacitive TouchScreen"` (goodix driver; RG DS, ARC-D),
  `"Hynitron cst3xx Touchscreen"` (hynitron_cstxxx driver; RG353P/M/V).
  ARC-S has no touchscreen.
- **Audio** cards/mixers from the codec driver + DTS: the `audio_mixer` is the
  ALSA **simple-mixer control** name used by `amixer sset '<mixer>' <pct>% unmute`.
  All boards use `Line Out` (sun4i/H616 codec on H700, rk817 on RK3326/RK3566).
  The H700 codec also exposes a raw numid control (`Line Out Playback Volume`,
  numid=2) that is NOT a simple control and is unusable via `sset`/`cset`
  `<name>`; it must NOT be used as `audio_mixer`. RK3566 card is `rk817_int`
  except RG503/ARC/RG DS which use `rk817_ext`.
- **eMMC** present on RG353P/M/V, ARC-D, RG DS (`/dev/mmcblk1`), absent on
  RG353PS/VS, RG503, ARC-S.
- **HDMI** via DRM connector, identified by the stable `gpu_hdmi_connector`
  (e.g. `HDMI-A-1`) and resolved to a `cardN`-prefixed status path at init.
  Devices with a wired `&hdmi`/connector: 353 family, rg503, RG353M. ARC-D/S
  have a physical mini HDMI port but the DTS does not enable it yet; RG DS
  has none. (See TODO.md.)
- **Rumble** is an input-device force-feedback interface, not a sysfs write.
  `input_rumble_device_name` names the input device with `FF_RUMBLE`
  capability (e.g. `pwm-vibrator`, registered by the `pwm-vibra` driver);
  consumers upload/play/stop a rumble effect via `EVIOCSFF`/`EV_FF`. RK3566
  and the H700 40XX/CubeXX have it; RK3326 and the other H700 devices do not.
  (See `docs/research/traits.c` for the reference HAL.)
- `screen_rotation` is the userspace UI rotation in degrees (0/90/180/270),
  consumed by `platform.c`/the Allium port to rotate the SDL renderer. It is
  the single source of truth for UI orientation. On RK3326 it is 0: the DTS
  panel `rotation` property (e.g. `rk3326-anbernic-rg351p.dts`) is applied by
  the DRM driver, so the framebuffer presented to userspace is already
  upright. RK3566 devices rely on the trait instead (ARC=90, RG353 family=270,
  RG503/RG DS=0); their kernel DTS/panel drivers do not rotate. The kernel
  fbcon boot-console rotation (`fbcon=rotate:1` in `rk3566/boot.env`) is a
  separate layer that only affects the transient pre-UI console and is
  documented there; it is not trait-derived because bootargs are baked at
  image build time and cannot read the runtime traits file.

### 4. Strict parser contract

UIs mirror `docs/research/traits.c` (the reference implementation) or
`minime/ui/minui/workspace/minime/platform/traits.c`:

- A schema table maps keys to struct fields (string or int).
- Parsing fails loudly on **unknown keys**, **missing required keys**, and
  **malformed integers** — never silently ignores input.
- Optional keys absent from the file stay empty / `-1`.
- `screen_aspect` is derived from `screen_width`/`screen_height` when not
  present in the file.

`platform.c` (MinUI) / `minime/mod.rs` (Allium) consume the resolved struct
and own all layout and behaviour decisions; they contain no device-specific
flags or resolution logic.

## Consequences & Benefits

- **Single source of truth**: hardware facts live in the DTBs + trait files;
  `check-traits.sh` validates the schema and `parent=` chain statically.
- **Drift is caught**: the strict parser and the DTB comparison in
  `check-traits.sh` make a wrong or missing trait a loud error.
- **Easy new devices**: a new base device is one `.ini`; a panel revision is
  a 6-line file with `parent=`.
- **Porting is trivial**: a new UI copies `docs/research/traits.c` and gets a
  fully-resolved struct with no per-device code.

## References

- `docs/research/traits.c` / `traits.h` — reference parser implementation.
- `minime/boards/*/traits/` — the trait files themselves (source of truth).
- `docs/adr/0005-cpu-governor-and-frequency-traits.md` — CPU clock semantics.
- `docs/research/firstboot-device-selector.md` — DTB detection & selection.
