# ADR 0025: H700 Device Detection

## Status

Accepted

## Context

RK3566 and RK3326 already auto-detect the device:

- RK3566: the rgxx3 U-Boot board reads a board-id resistor on SARADC channel 1 and sets `fdtfile`; `boot.cmd` loads `.minime/devices/${fdtfile}`.
- RK3326: `first-boot-probe.sh` (initramfs) probes SDIO/USB and writes `device.cfg`, honored by `boot.cmd`.

Allwinner H700 has no board-id ADC. Today every H700 device boots the default `sun50i-h700-anbernic-rg35xx-sp.dtb`; the other 13 H700 DTBs (rg28xx, rg34xx/-sp, rg35xx-2024/-h/-plus/-pro plus `-rev6`/`-v2-panel` variants, rg40xx-h/-v, rgcubexx) are staged in `.minime/devices/` but never selected. Traits resolve every H700 device to `rg35xx-sp-v1`, so non-SP-v1 hardware gets the wrong panel init, keymap, and backlight. This is not real detection.

LPDDR3/LPDDR4 is a per-unit RAM variant, not a model signal: Rocknix ships every H700 model in both and picks the U-Boot binary by `vdd-dram` microvolts (1.2 V vs 1.1 V). Minime already swaps the DDR3 U-Boot via the initramfs DCDC3 check, so RAM type is handled independently of model detection.

## Decision

H700 detection = a first-boot multi-signal probe (initramfs) that identifies the model, writes `device.cfg`, and reboots; a blind device-selector remains only as a last-resort fallback for panels that do not report an ID.

### Probe signals

1. **MIPI display ID (primary)** — the `panel-mipi-*` driver (`CONFIG_DRM_PANEL_MIPI=y`) reads `MIPI_DCS_GET_DISPLAY_ID` over the SPI (DBI) transport right after panel reset, *before* the init sequence, and logs `MIPI Display ID: %06x` to dmesg. The read therefore succeeds even when booted with the wrong panel DTB, because every H700 DTB carries a generic `panel-mipi-dpi-spi` node. A first-boot probe greps dmesg for the ID and looks it up in a panel→model table.
2. **SARADC stick channels** — devices with analog sticks (rg35xx-h, rg40xx-h/v, rgcubexx) wire them as `adc-joystick` over the SoC SARADC; the raw saradc channels can be probed for activity.
3. **Wi-Fi/BT presence** — rg28xx and rg35xx-2024 have neither; every other H700 device has both.
4. **Lid/hall sensor** — clamshells (rg35xx-sp, rg34xx-sp) expose a lid switch (`gpio-keys-lid`).
5. **Battery design capacity** — the AXP717 gas gauge reports model-specific mAh (`charge_full_design`); to be calibrated empirically per device.

DDR3/DDR4, RGB stick LEDs (40xx/cube), and the RGB LED (rg35xx-2024) are cross-checks, not discriminators.

### Flow

1. First boot loads the default DTB; the panel driver logs the real display ID.
2. The probe reads display ID + sticks + Wi-Fi + lid, resolves the model, writes `device.cfg`, clears the marker, and reboots fast.
3. Subsequent boots load `.minime/devices/${device}` via `boot.cmd`.
4. If the display ID is unreadable (driver logs `Unknown`), fall back to the blind selector: rumble/LED-coded DTB cycling over ~2 s reboot cycles (from the superseded `research/firstboot-device-selector.md`).

### Prerequisite

Ship the panel firmware for every supported H700 panel (`firmware/panels/*.panel`, `CONFIG_EXTRA_FIRMWARE`). Today only `anbernic,rg35xx-plus-panel.panel` ships; without the others, even a correctly detected panel fails to initialize.

## Consequences

- Real H700 detection without a board-id ADC: one image boots any H700 device.
- The display-ID read removes most of the "flying blind" problem — the panel is identified automatically; the selector is reduced to a rare fallback.
- The existing DDR3/DDR4 U-Boot swap stays; SPL dual DRAM training (single binary) is an optional later optimization, out of scope here.
- Supersedes `docs/research/firstboot-device-selector.md`.
