# 3. Allwinner H700 Power Management and System Suspend Strategy

* **Status**: Accepted
* **Date**: 2026-07-23

## Context

The Allwinner H700 SoC powers several handheld game consoles supported by Minime (Anbernic RG35XX SP, RG35XX Plus, RG35XX H, RG28XX, RG40XX H/V).

### Architectural Differences from Legacy Allwinner SoCs

Earlier Allwinner SoCs (H3, H5, H6) included an integrated **AR100 (ARISC) co-processor** running firmware (e.g. Crust SCP) to manage voltage rails, clock trees, and interrupt wakeups while the main CPU cores were powered down.

On the **Allwinner H700 (and H616)**:
- **No AR100 Co-processor**: The AR100/ARISC hardware co-processor was removed from the silicon.
- **PSCI Limitations**: TF-A (BL31) firmware (`PLAT=sun50i_h616`) implements basic power functions (`CPU_ON`, `CPU_OFF`, `SYSTEM_OFF`), but **does not support PSCI `CPU_SUSPEND` deep idle states**.
- **Boot Lockup Issue**: Enabling `CONFIG_ARM_PSCI_CPUIDLE=y` in Linux causes secondary CPU cores to enter PSCI idle without receiving timer interrupt wakeups, resulting in RCU grace-period kthread starvation (`rcu_preempt`) and kernel boot freezes.

---

## Decision

1. **Per-Board CPU Idle Scoping**:
   - Remove `CONFIG_ARM_PSCI_CPUIDLE` from [tiny-base.config](file:///Users/ilembitov/Projects/minime/alpine/board/common/tiny-base.config).
   - Keep `CONFIG_ARM_PSCI_CPUIDLE=y` in [tiny-rk3326.config](file:///Users/ilembitov/Projects/minime/alpine/board/rk3326/tiny-rk3326.config) and [tiny-rk3566.config](file:///Users/ilembitov/Projects/minime/alpine/board/rk3566/tiny-rk3566.config).
   - Keep `ARM_PSCI_CPUIDLE` disabled on H700 ([tiny-h700.config](file:///Users/ilembitov/Projects/minime/alpine/board/h700/tiny-h700.config)).

2. **Active Runtime Idle**:
   - H700 uses standard ARM Cortex-A53 `wfi` (`wait-for-interrupt`) state for active CPU runtime idle.
   - Power draw in `wfi` is ~15mW per core (~0.2% battery/hr on a 3300mAh pack).

3. **System Suspend (Deep Sleep)**:
   - System suspend (`mem` / `SUSPEND_TO_RAM`) operates via standard Linux kernel PM and AXP717 PMIC integration.
   - Placing RAM into self-refresh, turning off display/audio/Wi-Fi, and setting PMIC outputs to low-power mode reduces total system power to ~10-15mW total (~30+ days standby).

---

## Power Optimization Benchmarks & Distro Best Practices (ROCKNIX, Knulli, MuOS)

### 1. CPU Frequency & Governor Tuning
- **Governor Selection**: Use `schedutil` with fast-switching enabled. `schedutil` dynamically ramps CPU frequency up for demanding emulation frames and drops frequency instantly during idle loops.
- **CPU Opp Tables**: Enforce lower frequency steps (down to 408 MHz) during light UI navigation to minimize voltage consumption.

### 2. AXP717 PMIC Regulator Control
- **Unused LDO Power Down**: Ensure LDOs powering unused peripherals (e.g. Wi-Fi/BT module when wireless is disabled in UI) are fully disabled via I2C rather than left in bypass/standby.
- **Power Button & Lid Handling**:
  - RG35XX SP features a Hall-effect lid sensor exposed as `gpio-keys` (`SW_LID`).
  - Closing lid triggers an event listener to execute `echo mem > /sys/power/state`.
  - Opening lid triggers GPIO interrupt to wake the SoC instantly.

### 3. Display, Backlight & Audio Power Down
- **Backlight Sequence**: Turn off PWM backlight (`bl_power = FB_BLANK_POWERDOWN`) *before* suspending DRM display pipeline to prevent backlight bleed or power leakage during sleep.
- **Audio Codec Mute**: Disable sun4i audio codec internal DAC/headphone amplifier prior to suspend to eliminate idle pops and static drain.

### 4. Wi-Fi & Bluetooth Power Management
- **SDIO LPS Deep**: Wi-Fi module (`rtl8821cs`) uses `rtw88_core.disable_lps_deep=Y` in `bootargs` to prevent latency spikes during online play. When Wi-Fi is disabled via OS toggle, power off regulator completely via RFKILL.

---

## Technical Summary

| State | Mechanism | Power Draw | Estimated Battery Life (3300mAh) |
|---|---|---|---|
| **Active Gaming** | 4x A53 @ 1.5 GHz + Mali G31 GPU | ~1.5W - 2.2W | 5 - 8 hours |
| **Active Idle (Menu)** | Cores in Cortex-A53 `wfi` | ~0.3W - 0.5W | 20 - 30 hours |
| **Deep Suspend (`mem`)** | RAM self-refresh + AXP717 sleep | ~10mW - 15mW | 30 - 45 days |
