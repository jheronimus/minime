# AXP717 Power Button Initialization on H700 - Research Findings

## Executive Summary

The AXP717 power button (POK) is a **hardware-level function** of the PMIC itself. U-Boot does NOT initialize or configure the power button — it is handled entirely by the AXP717 silicon before any software runs. If the power button doesn't work, the issue is either hardware (button/wiring), register misconfiguration by prior firmware, or a REG22H setting that changes POK behavior.

## 1. U-Boot AXP717 SPL Driver Analysis

### What the driver does
The U-Boot AXP717 SPL driver (`drivers/power/axp_spl.c`) is **minimal** — it only:
- Sets DCDC1/2/3 voltages via I2C (registers 0x83-0x85)
- Enables DCDC outputs (register 0x80)
- Checks chip version (register 0x00)
- Provides `do_poweroff()` via register 0x27 (bit 0)

### What the driver does NOT do
- **No power button (POK) initialization**
- No REG22H (PWROFF_EN) configuration
- No REG26H (IRQLEVEL/OFFLEVEL/ONLEVEL) configuration
- No interrupt configuration
- No sleep/wakeup configuration

### Local defconfig (alpine/board/h700/ddr3.defconfig)
```
CONFIG_R_I2C_ENABLE=y
CONFIG_SPL_I2C=y
CONFIG_SPL_SYS_I2C_LEGACY=y
CONFIG_SYS_I2C_MVTWSI=y
CONFIG_REGULATOR_AXP=y
CONFIG_AXP717_POWER=y
CONFIG_AXP_DCDC2_VOLT=940
CONFIG_AXP_DCDC3_VOLT=1200
```

### Upstream defconfig (anbernic_rg35xx_h700_defconfig)
Same I2C/PMIC config, with `CONFIG_AXP_DCDC3_VOLT=1100` (vs our 1200).

**Key observation**: Neither defconfig has any POK/power-button-related CONFIG options. There is no `CONFIG_AXP717_POWER_BUTTON` or similar — because the power button is hardware.

## 2. AXP717 Power Button (POK) — Hardware Behavior

From the AXP717 datasheet (V1.0/V1.2):

### Power-on Sources (when EN/PWRON pin = PWRON mode, the default)
1. **POK**: Press and hold for longer than "ONLEVEL" duration
2. VBUS low-to-high transition
3. VBAT low-to-high transition
4. IRQ low level for >16ms
5. Battery charged to normal (VBAT>3.3V and charging)

### Power-off Sources
1. **POK**: Press and hold for longer than "OFFLEVEL" duration
2. Software write "1" to REG27H[0]
3. VSYSGOOD high-to-low (VSYS < VOFF threshold)
4. DCDC output 15% below setting
5. DCDC output 130% above setting
6. Die temperature >145°C
7. LDO over current

### Critical Registers

#### REG22H (PWROFF_EN) — Controls POK power-off behavior
| Bit | Description | Default |
|-----|-------------|---------|
| 3 | LDO Over-Current as POWEROFF source enable | POR: 0 |
| 2 | Reserved | RO: 1 |
| 1 | PWRON > OFFLEVEL as POWEROFF source enable | POR: 1 |
| 0 | Function when REG22H[1]=1 and button event occurs: 0=Power-off, 1=Restart | POR: 0 |

**Critical finding**: REG22H[1]=1 (default) + REG22H[0]=0 (default) = pressing power button long enough does a **power-off**, not a restart. If REG22H[0] is set to 1 (by stock firmware or prior software), long-pressing power does a **restart** instead.

#### REG26H (IRQLEVEL/OFFLEVEL/ONLEVEL) — Button timing
| Bits | Description | Default |
|------|-------------|---------|
| 5:4 | IRQLEVEL: 00=1s, 01=1.5s, 10=2s, 11=2.5s | POR: 01b (1.5s) |
| 3:2 | OFFLEVEL: 00=4s, 01=6s, 10=8s, 11=10s | POR: 01b (6s) |
| 1:0 | ONLEVEL: 00=128ms, 01=512ms, 10=1024ms, 11=2048ms | POR: 10b (1024ms) |

**Default ONLEVEL = 1024ms**. The power button must be held for ~1 second to power on.

#### REG27H (Soft Poweroff)
| Bit | Description |
|-----|-------------|
| 0 | Write 1 to power off |
| 1 | Write 1 to restart |

## 3. The Power Button Lifecycle

```
[Device Off] → Press POK > ONLEVEL → AXP717 powers on → SoC boots → U-Boot SPL → U-Boot proper → Linux
                                                                                                   ↓
[Device On]  ← Press POK > OFFLEVEL → AXP717 powers off ← REG22H[0] controls ← Linux/shutdown
```

**The power button is NEVER configured by U-Boot or Linux.** It is purely hardware. The PMIC handles power-on/off autonomously.

## 4. Why the Power Button Might Not Work

### Scenario A: Power button doesn't turn ON the device
This means the AXP717 PMIC never receives the power-on signal. Causes:
1. **Hardware**: Broken button, bad solder joint, disconnected wire to PWRON pin
2. **Stock firmware register corruption**: If stock firmware modified REG22H or REG26H and the PMIC retained those settings (unlikely after power-off, since registers reset on POR)
3. **Dead battery**: If VBAT is below UVLO threshold and no VBUS is present, the PMIC cannot power on
4. **PMIC in fault state**: Over-voltage, over-temperature, or other protection triggered

### Scenario B: Power button doesn't SHUT DOWN the device
The power button shutdown in Linux is handled by the `axp20x-pek` driver. If the Linux kernel doesn't have the `axp20x-pek` driver loaded (or the `input` subsystem isn't configured), key presses won't trigger shutdown. However, the PMIC hardware still handles long-press power-off via REG22H regardless of Linux.

### Scenario C: Power button works but resets instead of powering off
This would indicate REG22H[0] = 1 (restart mode), which is not the default. Stock Anbernic firmware may set this.

## 5. Community Firmware Handling

### ROCKNIX
ROCKNIX uses the same upstream U-Boot defconfig for H700. They do NOT add any special POK/power-button configuration. Their U-Boot is essentially identical to upstream.

### Stock Anbernic Firmware
The stock firmware uses a different (proprietary) bootloader that likely configures the AXP717 registers differently. The stock firmware may set:
- REG22H[0] = 1 (restart on long press, not power-off)
- Different ONLEVEL/OFFLEVEL values
- Watchdog configuration

## 6. Comparison with AXP313 (H616 predecessor)

The AXP313 on H616 boards has similar POK behavior. The U-Boot driver for AXP313 also does NOT initialize the power button. This is consistent across all AXP PMIC variants — the power button is always hardware.

## 7. Linux Kernel Driver Stack

The Linux kernel handles the power button through:
1. **MFD driver** (`drivers/mfd/axp20x.c`): Registers `axp20x-pek` as an MFD cell
2. **PEK driver** (`drivers/input/misc/axp20x-pek.c`): Registers input device for KEY_POWER
3. **IRQ handling**: PEK_RIS_EDGE and PEK_FAL_EDGE interrupts generate key press/release events

The PEK driver exposes sysfs attributes:
- `/sys/class/input/inputN/startup` — ONLEVEL timing
- `/sys/class/input/inputN/shutdown` — OFFLEVEL timing

## 8. Recommendations

### For the "power button does nothing" issue
1. **First, verify hardware**: Test continuity of the power button and its connection to the AXP717 PWRON pin
2. **Check if battery has charge**: Connect USB and see if the device powers on
3. **Check stock firmware registers**: If possible, read REG22H and REG26H from stock firmware to see if they differ from defaults
4. **Try holding longer**: Default ONLEVEL is 1024ms (~1 second). The button must be held for this duration minimum.
5. **Check if the button is physically the power button**: On some H700 devices, the button labeled "power" might be wired differently

### For U-Boot configuration
No changes needed for the power button — it's hardware. The current defconfig settings are correct:
- `CONFIG_R_I2C_ENABLE=y` — enables R_I2C bus (needed for AXP717 I2C access)
- `CONFIG_SPL_I2C=y` — enables I2C in SPL
- `CONFIG_SPL_SYS_I2C_LEGACY=y` — uses legacy I2C API in SPL
- `CONFIG_REGULATOR_AXP=y` — enables AXP regulator support
- `CONFIG_AXP717_POWER=y` — enables AXP717 PMIC driver

## 9. Key Source Files

| File | Purpose |
|------|---------|
| `drivers/power/axp_spl.c` | U-Boot AXP SPL driver (DCDC only, no POK) |
| `drivers/power/regulator/axp_regulator.c` | U-Boot regulator driver (full DM support) |
| `drivers/mfd/axp20x.c` | Linux MFD driver (registers PEK cell) |
| `drivers/input/misc/axp20x-pek.c` | Linux PEK driver (KEY_POWER input) |
| `drivers/power/supply/axp20x_usb_power.c` | Linux USB power supply driver |
| `include/linux/mfd/axp20x.h` | Register definitions including AXP717 registers |

## 10. Datasheet References

- REG22H: PWROFF_EN (power-off enable and behavior)
- REG26H: IRQLEVEL/OFFLEVEL/ONLEVEL (button timing)
- REG27H: Soft Poweroff configure
- REG20H: PWRON status (read-only, shows power-on source)

Source: AXP717 Datasheet V1.0/V1.2 (X-Powers)
