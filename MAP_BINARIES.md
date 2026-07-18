# MAP_BINARIES: Firmware & Bootloader Assets

Binary blobs shared between Alpine and Buildroot.
Source of truth is the Alpine board tree.

## Common firmware (all boards)

Under `alpine/board/common/firmware/`:

| File | Purpose |
|---|---|
| `rtl_bt/rtl8821cs_config.bin` | Realtek RTL8821CS Bluetooth config |
| `rtl_bt/rtl8821cs_fw.bin` | Realtek RTL8821CS Bluetooth firmware |
| `rtw88/rtw8821c_fw.bin` | Realtek rtw88_8821c Wi-Fi firmware |

Used by H700 and RK3566 boards (built-in Wi-Fi/BT).

## H700 board firmware

Under `alpine/board/h700/firmware/panels/`:

| File | Purpose |
|---|---|
| `anbernic,rg35xx-plus-panel.panel` | MIPI DPI panel timing/init for H700 |

Referenced by kernel `CONFIG_EXTRA_FIRMWARE`. Buildroot's `external.mk`
and Alpine's `tiny-h700.config` both point here.

## RK3326 board firmware

Under `alpine/board/rk3326/firmware/`:

### USB Wi-Fi dongles

| File | Driver |
|---|---|
| `carl9170-1.fw` | ath9k_htc (Atheros USB) |
| `rt73.bin` | rt73 (Ralink USB) |
| `rt2870.bin` | rt2870 (Ralink USB) |
| `ath9k_htc/htc_9271-1.4.0.fw` | ath9k_htc (Atheros USB) |
| `ath10k/QCA9377/hw1.0/firmware-5.bin` | ath10k (Qualcomm) |
| `brcm/brcmfmac43143.bin` | brcmfmac (Broadcom USB) |

### Realtek Wi-Fi/BT

| File | Driver |
|---|---|
| `rtlwifi/rtl8188eufw.bin` | rtlwifi (Realtek USB) |
| `rtlwifi/rtl8192cufw.bin` | rtlwifi (Realtek USB) |
| `rtw88/rtw8723d_fw.bin` | rtw88 (Realtek SDIO) |
| `rtw88/rtw8822c_fw.bin` | rtw88 (Realtek SDIO) |
| `rtl_bt/rtl8723b_fw.bin` | Realtek BT |
| `rtl_bt/rtl8723d_fw.bin` | Realtek BT |
| `rtl_bt/rtl8822cu_fw.bin` | Realtek BT |

### MediaTek Wi-Fi/BT

| File | Driver |
|---|---|
| `mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin` | MediaTek MT7961 Wi-Fi |
| `mediatek/WIFI_RAM_CODE_MT7961_1.bin` | MediaTek MT7961 Wi-Fi |
| `mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin` | MediaTek MT7961 BT |
| `mediatek/mt7663pr2h.bin` | MediaTek MT7663 BT |
| `mediatek/mt7601u.bin` | MediaTek MT7601U Wi-Fi |

## Prebuilt bootloader binaries

Under `alpine/bootloader/`. Built by `.github/workflows/bootloader.yml`.
Both Alpine and Buildroot use these for image assembly.

| Board | Files |
|---|---|
| H700 | `u-boot-sunxi-with-spl.bin` |
| RK3326 | `idbloader.img`, `u-boot.itb` |
| RK3566 | `idbloader.img`, `u-boot.itb`, `rkbin/bl31.elf`, `rkbin/rk3566_ddr_1056MHz_v1.25.bin`, `rkbin/LICENSE.rkbin` |
