# 0005: Decoupled CPU Frequency Traits and Governor Policy

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-02

---

## Context & Problem Statement

MinUI and Allium frontends define 4 CPU performance levels:
- `0` = `CPU_SPEED_MENU` (UI navigation and pause menus)
- `1` = `CPU_SPEED_POWERSAVE` (8-bit handhelds: GB, GBC, NES)
- `2` = `CPU_SPEED_NORMAL` (16-bit / 32-bit handhelds: GBA, SNES, Genesis)
- `3` = `CPU_SPEED_PERFORMANCE` (3D / demanding systems: PS1, Arcade)

Previously, Minime's platform backend mapped `speed <= 1` to the Linux kernel governor string `"powersave"`.

### Issues Identified

1. **Linux `cpufreq` Governor Behavior**:
   In Linux kernel `cpufreq`, setting `scaling_governor = "powersave"` hard-locks the CPU at its lowest hardware frequency step (`480 MHz` on H700). It does not dynamically scale up under load.
2. **Emulation Slowdown**:
   At a `480 MHz` floor, software framebuffer scaling (`RGB565` -> `ARGB8888`) plus Gambatte Game Boy emulation takes ~22 ms per frame, causing frame rates to drop from 60 FPS to **45 FPS**.
3. **Upstream Intent Mismatch**:
   In original MinUI and Allium, `0-3` represented targeted CPU clock frequencies (MHz values), not Linux governor string swaps.

---

## Decision Drivers

- **UI-Agnostic Contract**: Minime must remain 100% UI-agnostic. Hardware frequency steps must be defined in traits, not hardcoded in UI launcher binaries.
- **Dynamic Load Scaling**: Light emulators should run at full 60 FPS without forcing maximum power consumption.
- **Performance Responsiveness**: Maximum performance mode (`3`) must eliminate frequency ramp-up latency.

---

## Decided Architecture

### 1. Default Boot Governor

OpenRC initialization (`init.d/ui` / `traits.sh`) sets `schedutil` (or `ondemand`) as the system-wide default governor on boot:

```sh
echo "schedutil" > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
```

### 2. Trait Specification (`platform.ini`)

Hardware traits define sysfs control paths and target clock frequencies (kHz) for each board architecture:

#### `minime/boards/h700/traits/platform.ini`
```ini
cpu_governor_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cpu_clock_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
cpu_clock_menu=720000
cpu_clock_powersave=1008000
cpu_clock_normal=1200000
cpu_clock_performance=1416000
```

#### `minime/boards/rk3326/traits/platform.ini`
```ini
cpu_governor_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cpu_clock_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
cpu_clock_menu=600000
cpu_clock_powersave=816000
cpu_clock_normal=1008000
cpu_clock_performance=1200000
```

#### `minime/boards/rk3566/traits/platform.ini`
```ini
cpu_governor_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
cpu_clock_path=/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
cpu_clock_menu=816000
cpu_clock_powersave=1008000
cpu_clock_normal=1416000
cpu_clock_performance=1800000
```

### 3. UI Execution Logic (`power.c` / Allium `mod.rs`)

When setting CPU speed level:

1. **`Menu` (0), `Powersave` (1), `Normal` (2)**:
   - Write `"schedutil"` to `cpu_governor_path`.
   - Write corresponding `cpu_clock_*` value to `cpu_clock_path` (`scaling_max_freq`).
2. **`Performance` (3)**:
   - Write `"performance"` to `cpu_governor_path` (locks CPU at maximum clock speed with zero ramp-up latency).
   - Write `cpu_clock_performance` to `cpu_clock_path`.

---

## Consequences & Benefits

- **60 FPS Performance**: Game Boy emulation runs smoothly at 60 FPS under `Powersave` (`1.008 GHz` cap on H700).
- **Clean Decoupling**: UI launchers read `cpu_clock_*` traits cleanly without hardcoding SoC frequency tables or fragile governor rules.
- **Optimized Power**: Low-power systems run with dynamic `schedutil` frequency scaling up to board-specific max frequency caps.
