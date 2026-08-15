# ADR 0020: Charger-triggered boot — power off unless software or user-initiated

* **Status**: Superseded
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Superseded by

The `init.d/charger` grace-window implementation was **removed** (2026-08-11):
its power-button grace window cannot detect the user's power press, because the
press that boots the device happens before evdev/pwrkey is up and is never
queued for the polling script. The device therefore powered off even when the
user deliberately pressed power while charging.

The problem itself is deferred to [docs/TODO.md](../TODO.md). Key finding:
the rk817 PMIC **does** expose an `ON_SOURCE` register (0xF5,
`RK817_ON_SOURCE_REG`; `OFF_SOURCE` 0xF6) recording the power-on reason
(PWRON key vs. USB/VDC plug-in vs. RTC alarm) — contrary to the "unavailable
on RK3566" claim below. It is not exported via sysfs, but can be exposed by a
small kernel patch or handled in U-Boot via
`ROCKCHIP_RK8XX_DISABLE_BOOT_ON_POWERON`. Until re-implemented, plugging in
while off leaves the device running, and the `.software_reboot` OTA bypass no
longer exists.

---

## Context & Problem Statement

These handhelds **auto-power-on when the charger is plugged in** while off
(rk817 PMIC on RK3566, AXP2202 on H700 treat AC insertion as power-on):

1. **Overnight drain**: a user plugs in to charge before bed; the device
   boots, stays running, and is low/dead by morning.
2. **OTA reboot stall**: the on-device updater (ADR 0003) applies an update
   and `reboot`s. If the charger is connected, the reboot lands back in
   "charger mode" — a boot state where only a charging screen is shown and
   the OS never finishes starting. The OTA appears to hang and the update is
   left half-applied.

Allium's built-in charging screen (suspend + "charging" overlay via
`PowerSettings.charging_screen`) is UI-specific, suspends instead of powering
off, and solves neither case. The desired behavior is that of a non-phone
appliance: **plugging in the charger while off must not leave the device
running.**

### What other firmwares do

- **Knulli** (`/usr/bin/charger` daemon): on charger-mode boot, shows charging
  status, waits ~4 s for a power-button press, then **suspends** (`mem`);
  powers off if unplugged. Known bugs: unplug-after-sleep boots instead of
  shutting down (knulli-cfw/distribution#287); post-charge "mixed state"
  drains the battery (#140). Suspend is the root of these failures.
- **MuOS**: reads the AXP2202 PMIC `boot_mode` sysfs (H700) to know the boot
  source. The rk817 (RK3566) exposes **no** equivalent boot-source file — see
  the supersede note above.
- **Rocknix**: no unified charger-mode boot handling; relies on suspend
  semantics, with the same drain reports.

## Decision (superseded)

Replace the UI charging screen with a **UI-agnostic early-boot script** that
powers the device **off** (never suspend) when it was turned on *by the
charger*, unless the boot was software-initiated or the user pressed power:

1. **Software-reboot marker**: before calling `reboot`, the updater writes
   `.minime/config/.software_reboot`; the charger check treats a present
   marker as "software boot" and continues booting, then clears it. This
   fixes the OTA-stall case without the updater needing charger awareness.
2. **Charger-mode power-off check**: an init script (`/etc/init.d/charger`)
   runs before the UI and reads `power_charger_online_path` from the traits
   file. If the path is `na`/missing, skip. If the charger is offline, boot
  normally. If online with no marker, the device was powered on by the
  charger: wait a ~4 s power-button grace window; if pressed, boot normally
  (user wants AC use); else `poweroff`.
3. **Disable Allium charging screen**: `PowerSettings.charging_screen` set
   `false` via written `power.json` so Allium never takes over the display.

## Consequences

- **Positive**: appliance behavior (plug in while off leaves it off);
  overnight drain eliminated; OTA reboot completes even when charging.
- **Negative**: a genuinely automatic charger-triggered power-on that the
  user wanted to keep running powers off after ~4 s — the accepted trade-off.
- **Fragility**: the grace window requires the input device to be readable
  early; must fail open (boot normally) if the button can't be polled.
- **Critically-low battery**: if too low to complete poweroff, behavior is
  hardware-dependent (may stay black until charged) — same as every CFW.## Alternatives considered

- **Suspend instead of poweroff (Knulli model)**: rejected — suspend leaves
  the device powered, causing the battery-drain / mixed-state bugs upstream.
- **PMIC boot-source sysfs (MuOS)**: originally rejected for RK3566 because
  the rk817 driver exposes no boot-source file. Revisit via `ON_SOURCE` (see
  supersede note).
- **Allium charging screen (status quo)**: rejected — UI-specific, suspends
  rather than powers off, and doesn't fix the OTA-reboot stall.
