# Input Subsystem & Hotkeys

## Problem
Gaming handhelds use varying button controllers (GPIO buttons, ADC analog sticks, I2C touchscreens) with divergent keycodes and physical layouts across hardware revisions.

## Solution
Input drivers register standard Linux `evdev` event nodes. Device traits (`.minime/traits`) specify `input_type` and analog stick counts. A background key monitor (`keymon`) and standardized hotkey combinations (e.g. Menu + Start/Select) ensure uniform system controls across all launchers and emulators.

## Examples
- Device traits registry: `packages/components/boards/h700/traits/`
- Trait input schema: `docs/traits/TRAITS.md`

## See Also
- Traits specification: [`docs/traits/TRAITS.md`](../traits/TRAITS.md)
- Board trait definitions: [`packages/components/boards/`](../../packages/components/boards/)
