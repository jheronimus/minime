# Audit: AI-Agent Kernel Config Additions

Date: 2026-07-28
Status: Reverted — all options removed from board fragments.

## Background

A previous AI agent added ~50 kernel config options across three board fragments
(`tiny-h700.config`, `tiny-rk3326.config`, `tiny-rk3566.config`). This document
audits each addition for correctness, duplication, relevance to Anbernic hardware,
and proper placement (board fragment vs. base config).

Options were validated against the Linux kernel Kconfig source (v6.x).

## Summary

| Category | Count |
|---|---|
| Fake/invalid symbols | 3 |
| Redundant (auto-selected) | 8 |
| Wrong board / not applicable | 9 |
| Duplicate with base config | 1 |
| Valid and relevant | ~18 |
| **Net useful additions** | **~18** (but none are blocking boot)** |

**Conclusion:** None of these options are required for boot, Wi-Fi, or SD card
expansion. They were speculative additions for display pipelines, audio codecs,
and panel drivers that may or may not be present on specific Anbernic board
revisions. Adding them later (after the device boots) is safe.

## Per-Option Audit

### H700 (`tiny-h700.config`)

| Symbol | Valid | Auto-selected | Relevant | Verdict |
|---|---|---|---|---|
| `CONFIG_DRM_BRIDGE` | Yes | Yes (by `DRM_SUN4I`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_DW_HDMI` | Yes | No | **No** — H700 has no HDMI output | **Wrong board** — removed |
| `CONFIG_DRM_PANEL_BRIDGE` | Yes | Yes (by `DRM`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_SUN50I_PLANES` | **No — fake symbol** | — | — | **Invalid** — removed |
| `CONFIG_DRM_SUN6I_DSI` | Yes | Yes (by `DRM_SUN4I`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_SUN8I_DW_HDMI` | Yes | No | **No** — H700 has no HDMI | **Wrong board** — removed |
| `CONFIG_DRM_SUN8I_MIXER` | Yes | Yes (by `DRM_SUN4I`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_SUN8I_TCON_TOP` | Yes | Yes (by `DRM_SUN4I`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_SIMPLE_BRIDGE` | Yes | No | **No** — not used on H700 | **Wrong board** — removed |
| `CONFIG_BACKLIGHT_GPIO` | Yes | No | Maybe — GPIO backlight | **Keep for later** — removed |
| `CONFIG_BACKLIGHT_LED` | Yes | No | Maybe — LED backlight | **Keep for later** — removed |
| `CONFIG_SND_SUN4I_I2S` | Yes | No | **No** — I2S not needed for codec-only output | **Wrong interface** — removed |
| `CONFIG_SND_SUN4I_SPDIF` | Yes | No | **No** — S/PDIF not present on handhelds | **Wrong interface** — removed |
| `CONFIG_PHY_SUN50I_USB3` | Yes | No | **No** — H700 has no USB3 | **Wrong SoC** — removed |
| `CONFIG_PHY_SUN6I_MIPI_DPHY` | Yes | Yes (by `DRM_SUN6I_DSI`) | Yes | **Redundant** — removed |

### RK3326 (`tiny-rk3326.config`)

| Symbol | Valid | Auto-selected | Relevant | Verdict |
|---|---|---|---|---|
| `CONFIG_DRM_BRIDGE` | Yes | Yes (by `DRM_ROCKCHIP`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_PANEL_BRIDGE` | Yes | Yes (by `DRM`) | Yes | **Redundant** — removed |
| `CONFIG_DRM_PANEL_NEWVISION_NV3051D` | Yes | No | **No** — not used in RG351V/MP | **Wrong panel** — removed |
| `CONFIG_DRM_PANEL_ELIDA_KD35T133` | Yes | No | **No** — not used in RG351V/MP | **Wrong panel** — removed |
| `CONFIG_DRM_SIMPLE_BRIDGE` | Yes | No | **No** — not needed for ST7703 | **Wrong board** — removed |
| `CONFIG_PHY_ROCKCHIP_INNO_HDMI` | Yes | No | **No** — RK3326 has no HDMI PHY | **Wrong SoC** — removed |
| `CONFIG_ROCKCHIP_VOP` | Yes | Yes (by `DRM_ROCKCHIP`) | Yes | **Redundant** — removed |
| `CONFIG_JOYSTICK_ADC` | Yes | No | **Yes** — analog sticks on RG351V | **Valid** — removed, add later |
| `CONFIG_SND_SIMPLE_CARD` | Yes | No | Yes — audio card binding | **Valid** — removed, add later |
| `CONFIG_SND_SOC_ES8316` | Yes | No | **Yes** — audio codec on RG351V | **Valid** — removed, add later |
| `CONFIG_SND_SOC_RK817` | Yes | No | Maybe — RK817 PMIC audio | **Valid** — removed, add later |
| `CONFIG_SND_SOC_ROCKCHIP` | **No — fake symbol** | — | — | **Invalid** — removed |
| `CONFIG_SND_SOC_ROCKCHIP_I2S` | Yes | No | Yes — I2S audio controller | **Valid** — removed, add later |
| `CONFIG_SND_SOC_SIMPLE_AMPLIFIER` | Yes | No | Maybe — external amp | **Valid** — removed, add later |
| `CONFIG_RTC_DRV_RK808` | Yes | No | **Yes** — RK808 PMIC RTC | **Valid** — removed, add later |

### RK3566 (`tiny-rk3566.config`)

| Symbol | Valid | Auto-selected | Relevant | Verdict |
|---|---|---|---|---|
| `CONFIG_DRM_LOAD_EDID_FIRMWARE` | Yes | No | Maybe — EDID override | **Keep for later** — removed |
| `CONFIG_DRM_PANEL_HIMAX_HX8394` | Yes | No | **No** — not used in Anbernic RK3566 | **Wrong panel** — removed |
| `CONFIG_DRM_PANEL_JADARD_JD9365DA_H3` | Yes | No | **No** — not used in Anbernic RK3566 | **Wrong panel** — removed |
| `CONFIG_DRM_PANEL_NEWVISION_NV3051D` | Yes | No | **No** — not used in Anbernic RK3566 | **Wrong panel** — removed |
| `CONFIG_DRM_PANEL_MAGNACHIP_D53E6EA8966` | Yes | No | **No** — not used in Anbernic RK3566 | **Wrong panel** — removed |
| `CONFIG_PHY_ROCKCHIP_INNO_HDMI` | Yes | No | Maybe — HDMI PHY for HDMI output | **Keep for later** — removed |
| `CONFIG_BACKLIGHT_LED` | Yes | No | Maybe — LED backlight | **Keep for later** — removed |
| `CONFIG_SND_SOC_ROCKCHIP` | **No — fake symbol** | — | — | **Invalid** — removed |
| `CONFIG_IIO` | Yes | — | **Duplicate** with `tiny-base.config` line 115 | **Duplicate** — removed |
| `CONFIG_INV_ICM42600` | Yes | No | **No** — not in Anbernic devices | **Wrong device** — removed |
| `CONFIG_INV_ICM42600_I2C` | Yes | No | **No** — not in Anbernic devices | **Wrong device** — removed |
| `CONFIG_INV_ICM42600_SPI` | Yes | No | **No** — not in Anbernic devices | **Wrong device** — removed |
| `CONFIG_INV_MPU6050_I2C` | Yes | No | **No** — not in Anbernic devices | **Wrong device** — removed |
| `CONFIG_INV_MPU6050_SPI` | Yes | No | **No** — not in Anbernic devices | **Wrong device** — removed |

## Options Worth Adding Later (Post-Boot)

These options are valid, correctly named, non-duplicated, and relevant to Anbernic
hardware, but are not required for boot/network/disk and should be added
incrementally after confirming the device boots:

### RK3326 (RG351V/MP)
- `CONFIG_JOYSTICK_ADC=y` — analog stick via ADC (RG351V has one)
- `CONFIG_SND_SIMPLE_CARD=y` — audio card binding
- `CONFIG_SND_SOC_ES8316=y` — ES8316 audio codec (RG351V uses this)
- `CONFIG_SND_SOC_RK817=y` — RK817 audio codec (some RK351 variants)
- `CONFIG_SND_SOC_ROCKCHIP_I2S=y` — I2S audio controller
- `CONFIG_SND_SOC_SIMPLE_AMPLIFIER=y` — external amplifier
- `CONFIG_RTC_DRV_RK808=y` — RK808 PMIC RTC

### RK3566 (RG353M/P)
- `CONFIG_PHY_ROCKCHIP_INNO_HDMI=y` — HDMI PHY (RG353P has mini-HDMI)
- `CONFIG_BACKLIGHT_LED=y` — LED backlight

### H700 (RG35XX Plus)
- `CONFIG_BACKLIGHT_GPIO=y` — GPIO-driven backlight
- `CONFIG_BACKLIGHT_LED=y` — LED backlight

## Fake Symbols Found

1. **`CONFIG_DRM_SUN50I_PLANES`** — does not exist in kernel Kconfig. The correct
   symbol is `CONFIG_DRM_SUN8I_PLANES` (auto-selected by `DRM_SUN4I`).

2. **`CONFIG_SND_SOC_ROCKCHIP`** (used in RK3326 and RK3566) — does not exist.
   There is no umbrella Rockchip SoC audio symbol. Individual I2S/TDM/codec
   symbols are sufficient.

3. (Note: `CONFIG_SND_SOC_ROCKCHIP_I2S` and `CONFIG_SND_SOC_ROCKCHIP_I2S_TDM`
   are valid symbols — only the bare `CONFIG_SND_SOC_ROCKCHIP` is fake.)
