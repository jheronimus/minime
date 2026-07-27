# Allwinner H700 Power Management & AXP717 Hardware Specifications

## Executive Summary

The Allwinner H700 SoC powers several handheld game consoles supported by Minime (Anbernic RG35XX SP, RG35XX Plus, RG35XX H, RG28XX, RG40XX H/V). This document details the power management architecture, PMIC (AXP717) hardware registers, CPU idle/suspend strategies, and distro best practices.

---

## 1. Architectural Overview & PSCI Limitations

Earlier Allwinner SoCs (H3, H5, H6) included an integrated **AR100 (ARISC) co-processor** running firmware (e.g. Crust SCP) to manage voltage rails, clock trees, and interrupt wakeups while the main CPU cores were powered down.

On the **Allwinner H700 (and H616)**:
- **No AR100 Co-processor**: The AR100/ARISC hardware co-processor was removed from the silicon.
- **PSCI Limitations**: TF-A (BL31) firmware (`PLAT=sun50i_h616`) implements basic power functions (`CPU_ON`, `CPU_OFF`, `SYSTEM_OFF`), but **does not support PSCI `CPU_SUSPEND` deep idle states**.
- **Boot Lockup Issue**: Enabling `CONFIG_ARM_PSCI_CPUIDLE=y` in Linux causes secondary CPU cores to enter PSCI idle without receiving timer interrupt wakeups, resulting in RCU grace-period kthread starvation (`rcu_preempt`) and kernel boot freezes.

### CPU Idle & Suspend Decisions

1. **Per-Board CPU Idle Scoping**:
   - `ARM_PSCI_CPUIDLE` disabled on H700 (`tiny-h700.config`).
   - `CONFIG_ARM_PSCI_CPUIDLE=y` kept for RK3326 and RK3566.

2. **Active Runtime Idle**:
   - H700 uses standard ARM Cortex-A53 `wfi` (`wait-for-interrupt`) state for active CPU runtime idle.
   - Power draw in `wfi` is ~15mW per core (~0.2% battery/hr on a 3300mAh pack).

3. **System Suspend (Deep Sleep)**:
   - System suspend (`mem` / `SUSPEND_TO_RAM`) operates via standard Linux kernel PM and AXP717 PMIC integration.
   - Placing RAM into self-refresh, turning off display/audio/Wi-Fi, and setting PMIC outputs to low-power mode reduces total system power to ~10-15mW total (~30+ days standby).

---

## 2. AXP717 PMIC Hardware & Power Button (POK) Analysis

The AXP717 power button (POK) is a **hardware-level function** of the PMIC itself. U-Boot does NOT initialize or configure the power button — it is handled entirely by the AXP717 silicon before any software runs.

### Power-on Sources (when EN/PWRON pin = PWRON mode, default)
1. **POK**: Press and hold for longer than `ONLEVEL` duration (default: 1024ms).
2. VBUS low-to-high transition.
3. VBAT low-to-high transition.
4. IRQ low level for >16ms.
5. Battery charged to normal (VBAT > 3.3V and charging).

### Power-off Sources
1. **POK**: Press and hold for longer than `OFFLEVEL` duration (default: 6s).
2. Software write `1` to REG27H[0].
3. VSYSGOOD high-to-low (VSYS < VOFF threshold).
4. DCDC output 15% below setting / 130% above setting.
5. Die temperature > 145°C or LDO over-current.

### Critical PMIC Registers

#### REG22H (PWROFF_EN) — Controls POK power-off behavior
| Bit | Description | Default |
|-----|-------------|---------|
| 3 | LDO Over-Current as POWEROFF source enable | POR: 0 |
| 2 | Reserved | RO: 1 |
| 1 | PWRON > OFFLEVEL as POWEROFF source enable | POR: 1 |
| 0 | Function when REG22H[1]=1 and button event occurs: 0=Power-off, 1=Restart | POR: 0 |

#### REG26H (IRQLEVEL/OFFLEVEL/ONLEVEL) — Button timing
| Bits | Description | Default |
|------|-------------|---------|
| 5:4 | IRQLEVEL: 00=1s, 01=1.5s, 10=2s, 11=2.5s | POR: 01b (1.5s) |
| 3:2 | OFFLEVEL: 00=4s, 01=6s, 10=8s, 11=10s | POR: 01b (6s) |
| 1:0 | ONLEVEL: 00=128ms, 01=512ms, 10=1024ms, 11=2048ms | POR: 10b (1024ms) |

---

## 3. Power Optimization Benchmarks & Distro Best Practices

### CPU Frequency & Governor Tuning
- **Governor Selection**: Use `schedutil` with fast-switching enabled. `schedutil` dynamically ramps CPU frequency up for demanding emulation frames and drops frequency instantly during idle loops.
- **CPU Opp Tables**: Enforce lower frequency steps (down to 408 MHz) during light UI navigation to minimize voltage consumption.

### Display, Backlight & Audio Power Down
- **Backlight Sequence**: Turn off PWM backlight (`bl_power = FB_BLANK_POWERDOWN`) *before* suspending DRM display pipeline to prevent backlight bleed or power leakage during sleep.
- **Audio Codec Mute**: Disable sun4i audio codec internal DAC/headphone amplifier prior to suspend to eliminate idle pops and static drain.

### Wi-Fi & Bluetooth Power Management
- **SDIO LPS Deep**: Wi-Fi module (`rtl8821cs`) uses `rtw88_core.disable_lps_deep=Y` in `bootargs` to prevent latency spikes during online play. When Wi-Fi is disabled via OS toggle, power off regulator completely via RFKILL.

---

## Technical Summary

| State | Mechanism | Power Draw | Estimated Battery Life (3300mAh) |
|---|---|---|---|
| **Active Gaming** | 4x A53 @ 1.5 GHz + Mali G31 GPU | ~1.5W - 2.2W | 5 - 8 hours |
| **Active Idle (Menu)** | Cores in Cortex-A53 `wfi` | ~0.3W - 0.5W | 20 - 30 hours |
| **Deep Suspend (`mem`)** | RAM self-refresh + AXP717 sleep | ~10mW - 15mW | 30 - 45 days |
