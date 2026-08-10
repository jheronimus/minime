# 0020: Charger-triggered boot — power off unless software or user-initiated

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

These handhelds **auto-power-on when the charger is plugged in** while off.
The hardware (rk817 PMIC on RK3566, AXP2202 on H700) treats AC insertion as a
power-on event. Consequences:

1. **Overnight drain**: a user plugs in to charge before bed; the device
   boots, stays running, and is low/dead by morning.
2. **OTA reboot stall**: the on-device updater (ADR 0017) applies an update
   and `reboot`s. If the charger is connected, the reboot lands back in
   "charger mode" — a boot state where only a charging screen is shown and
   the OS never finishes starting. The OTA appears to hang and the update is
   left half-applied.

Allium currently shows a built-in charging screen when charging (suspend +
"charging" overlay via `PowerSettings.charging_screen`). That is UI-specific,
suspends the device instead of powering off, and does not solve either case —
it must be *disabled* for Minime and replaced with system-level handling.

The desired behavior is that of a non-phone appliance: **plugging in the
charger while off must not leave the device running.**

### What other firmwares do

- **Knulli** (`/usr/bin/charger` daemon): on charger-mode boot, shows
  charging status, waits ~4 s for a power-button press, then **suspends**
  (`mem`); powers off if unplugged. Known bugs: unplug-after-sleep boots
  instead of shutting down (knulli-cfw/distribution#287); post-charge
  "mixed state" drains the battery (#140). The suspend model is the root of
  these failures.
- **MuOS**: reads the AXP2202 PMIC `boot_mode` sysfs (H700) to know the boot
  source. The rk817 (RK3566) exposes **no** equivalent boot-source file, so
  this is unavailable on the RK3566.
- **Rocknix**: no unified charger-mode boot handling; relies on suspend
  semantics, with the same drain reports.

## Decision

Replace the UI charging screen with a **UI-agnostic early-boot script** that
powers the device **off** (not suspend) when it was turned on *by the
charger*, unless the boot was software-initiated or the user pressed power.

### 1. Boot-state marker for software reboots

Software reboots (the OTA updater, and anything else that calls `reboot`)
must bypass charger-mode so the OS finishes starting:

- Before calling `reboot`, the updater writes `.minime/config/.software_reboot`.
- The charger check treats a present marker as "boot was requested by
  software" and **continues booting**, then clears the marker.
- This fixes the OTA-stall case (scenario 2) without the updater needing any
  charger awareness.

### 2. Charger-mode power-off check (early boot)

An init script (`/etc/init.d/charger`) runs **before the UI** and:

1. Reads `power_charger_online_path` from the traits file
   (`/mnt/sdcard/.minime/traits`). If the path is `na`/missing (e.g. RK3326),
   skip — no charger detection, boot normally.
2. If the charger is **not online**, boot normally.
3. If `.software_reboot` is present, clear it and boot normally.
4. Otherwise the device was powered on by the charger with no software
   intent: wait a short **power-button grace window** (~4 s, mirroring
   Knulli) for the user to press power. If pressed, boot normally (the user
   wants to use it on AC). If not pressed, **`poweroff`**.
5. **Power off, never suspend.** Suspend is what leaves the device
   "on-but-asleep" draining the battery (Knulli's bugs). A full poweroff lets
   the battery charge with the SoC off — the fastest, safest charge.

### 3. Disable Allium's charging screen

`PowerSettings.charging_screen` (Allium) is set to `false` via a written
`power.json` so Allium boots normally on charge and never takes over the
display. This is a UI-agnostic decision; the script handles power, not the
charging indicator.

## Consequences

- **Positive**: plugging in while off leaves the device off (appliance
  behavior); overnight drain eliminated; the OTA reboot completes even when
  charging; deliberate power-on while plugged in still works via a single
  power press.
- **Negative**: a genuinely automatic charger-triggered power-on that the
  user wanted to keep running (without touching the button) now powers off
  after ~4 s. This is the accepted trade-off for the appliance behavior; the
  user presses power to keep it on.
- **Fragility**: the power-button grace window requires the input device to
  be readable early. The script must not block boot if the button can't be
  polled (fail open = boot normally).
- **Critically-low battery**: if the battery is too low to complete the
  poweroff, behavior is hardware-dependent (may stay black until charged) —
  same as every CFW; not handled in software.

## Alternatives considered

- **Suspend instead of poweroff (Knulli model)**: rejected — suspend leaves
  the device powered, causing the battery-drain / mixed-state bugs seen
  upstream.
- **PMIC boot-source sysfs (MuOS)**: rejected for RK3566 — the rk817 driver
  does not expose a boot-source file (only the H700's AXP2202 does).
- **Allium charging screen (status quo)**: rejected — UI-specific, suspends
  rather than powers off, and doesn't fix the OTA-reboot stall.
