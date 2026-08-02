# 0007: H700 AXP PMIC — RSB Bus Driver Panics on Boot

* **Status**: Accepted (Revert)
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-03

---

## Context & Problem Statement

The RG35XX SP (H700, Allwinner H700 SoC) uses an AXP PMIC for power management, including the power button (`INPUT_AXP20X_PEK`). On the working Aug-1 2026 build, the PMIC was accessed over **I2C** (`CONFIG_MFD_AXP20X_I2C=y`), and the device booted and powered on/off correctly.

Commit `12ee3f3` ("fix(h700): enable RSB bus and AXP20X RSB driver for power controller") added:

```kconfig
CONFIG_SUNXI_RSB=y
CONFIG_MFD_AXP20X_RSB=y
```

intending to access the PMIC over the RSB bus instead of / in addition to I2C.

### Symptom

The first boot with the new kernel panics:

```
user pgtable: 4k pages, 48-bit VAs
Internal error: Oops: 000000009200004f [#1] SMP
CPU: 1 UID: 0 PID: 1 Comm: init Tainted: G W 7.1.5
pc/lr in userspace (PID 1 /init), registers contain "backlight" strings
Kernel panic - not syncing: Aiee, killing interrupt handler!
```

The panic occurs during the initramfs backlight setup (`echo 5 >/sys/class/backlight/*/brightness`) immediately after mounting the EROFS system image and advancing the clock. No kernel panic dump is persisted to the SD card; only the initramfs `boot.log` is available, which stops at "Advancing system time".

## Root Cause Isolation

To rule out the OTA delivery mechanism, every non-kernel boot component was byte-compared between the working Aug-1 image and the panicking Aug-2 OTA build:

| Component | Old (boots) | New (panics) | Identical? |
|---|---|---|---|
| `boot.scr` payload | — | — | **Yes** (only uImage header timestamp differs) |
| `.minime/dtb` (`rg35xx-sp`) | `69e30c94…` | `69e30c94…` | **Yes** |
| initramfs `/init` | — | — | **Yes** |
| initramfs `busybox` | `999cb969…` | `999cb969…` | **Yes** |
| **kernel** | `b35b50fb…` (no RSB) | (with RSB) | **No** |

The only differing artifact is the kernel. The only kernel-affecting commit between the two builds is `12ee3f3` (RSB + `AXP20X_RSB`). The H700 RSB driver change therefore causes the boot-time panic on real hardware.

## Decision

Revert the RSB additions in `minime/boards/h700/tiny-h700.config`:

- Remove `CONFIG_SUNXI_RSB=y`
- Remove `CONFIG_MFD_AXP20X_RSB=y`
- Restore the working AXP20X-over-I2C configuration (`CONFIG_MFD_AXP20X_I2C=y`, `CONFIG_REGULATOR_AXP20X=y`, `CONFIG_INPUT_AXP20X_PEK=y`)

The power button continues to work via the I2C AXP path that shipped in the known-good Aug-1 image.

## Consequences

- H700 devices boot reliably again with the PMIC accessed over I2C.
- If RSB access is later desired (e.g. for features that require the RSB-backed PMIC), it must be validated on-device with a matching DTS/RSB node before re-enabling.
- The OTA delivery mechanism is confirmed sound: archives are byte-exact, and `.minime/.system` extraction clean-replaces/overlays correctly.
