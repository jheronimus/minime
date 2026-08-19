# ADR 0029: Default Hotkeys & Input Mapping Architecture

## Status
Accepted

## Context
Minime runs on Anbernic handhelds (H700, RK3566, RK3326) with distinct input topologies:
- Button layouts: standard 4-button (A/B/X/Y), 6-button Sega arcade (A/B/C/X/Y/Z on RG ARC).
- Analog sticks: dual-stick (RG35XX-H, RG353), single-stick vertical (RG40XX-V, RG351V), stickless (RG28XX, RG35XX SP).
- Function buttons: most devices provide a dedicated **`F` / `MENU`** button (`key_menu`), while older RK3326 models (RG351P/M/MP) lack it.
- Kernel input nodes: buttons (`gpio-keys-*`) and analog sticks (`adc-joystick`) register as separate evdev device descriptors.

Frontend launchers (MinUI, Allium) require a single, consistent input mapping and hotkey scheme across all form factors.

## Decision

### 1. Hotkey Modifier Priority
- **Primary default**: The dedicated **`F` / `MENU`** button (`key_menu != na`) is the global hotkey modifier across all platforms.
- **Fallback**: On devices lacking a dedicated function button (`key_menu = na`, e.g. RG351P/M/MP), the platform HAL transparently falls back to **`SELECT`** as the modifier for hotkey combos.

### 2. Standard Emulator & Launcher Shortcuts
Shortcuts follow an AmberELEC-inspired standard:

| Function | Combination | Behavior |
| :--- | :--- | :--- |
| **In-Game Menu** | `F` / `MENU` (tap) | Opens launcher/core quick menu |
| **Save State** | `Hotkey + R1` | Saves to current slot |
| **Load State** | `Hotkey + L1` | Loads from current slot |
| **Hold Fast Forward** | `Hotkey + R2` | Fast forwards while held |
| **Hold Rewind** | `Hotkey + L2` | Rewinds gameplay buffer while held |
| **Reset Game** | `Hotkey + B` | Soft resets the active core |
| **Save & Quit** | `Hotkey + START` | Saves state and exits to launcher |
| **Brightness** | `Hotkey + VolUp / VolDown` | Adjusts backlight brightness |
| **Volume** | `VolUp / VolDown` (native) | Direct ALSA volume adjustment |

### 3. Multi-Descriptor Input Polling (`input_stick_device_name`)
- Traits schema ([ADR 0011](0011-traits-schema.md)) defines `input_stick_device_name` (`adc-joystick` or `na`).
- Platform HAL (`platform.c` in MinUI, `input.rs` in Allium) opens all valid input descriptors (`input_gamepad`, `input_stick`, `input_power`, `input_volume`, `input_menu`) and multiplexes events into a unified pad state.

### 4. 6-Button Arcade Mapping (RG ARC)
- Devices exposing `key_c=306` and `key_z=309` map `C` and `Z` directly to `RETRO_DEVICE_ID_JOYPAD_X` and `RETRO_DEVICE_ID_JOYPAD_Y` (or core-specific 6-button bindings) for Genesis/MD and Capcom arcade fighting games.

## Consequences
- Uniform user muscle memory across all Minime handhelds and UI frontends.
- Zero collision between native volume rockers and backlight controls.
- Automatic graceful fallback on legacy devices without code duplication.

## References
- [ADR 0010](0010-ui-contract-and-traits.md) — UI Contract and Traits
- [ADR 0011](0011-traits-schema.md) — Hardware Traits Schema
- [AmberELEC Controls Guide](https://amberelec.org/guides/getting-to-know-amberelec.html)
- MinUI: `packages/ui/minui/workspace/minime/platform/` & `minarch/`
- Allium: `packages/ui/allium/crates/common/src/platform/minime/`
