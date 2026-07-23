# Specification: First-Boot Blind Device Selector

## Context & Problem

Handheld platforms like Allwinner H700 lack a unified hardware ADC pin for board detection (unlike RK3566). Booting an image with an incorrect DTB results in a non-functional or black screen due to display panel timing and backlight GPIO mismatches.

To support shipping a single unified image for H700 and platforms without automatic board detection, Minime requires a headless, first-boot device selector that allows the user to cycle DTBs until an image appears.

## System Architecture

```
                      [ First Boot / Unconfigured ]
                                   │
                                   ▼
                    [ Linux Kernel + Initramfs Boot ]
                                   │
                                   ▼
                    [ Check .minime/config/device_selected ]
                                   │
                     ┌─────────────┴─────────────┐
                  (Exists)                    (Missing)
                     │                           │
                     ▼                           ▼
              [ Normal Boot ]           [ Run Selector Service ]
                                                 │
                                                 ├── Listen /dev/input/event*
                                                 ├── Read DTB list from .minime/devices/
                                                 │
                             ┌───────────────────┴───────────────────┐
                       [ D-Pad UP/DOWN ]                        [ Button A ]
                             │                                       │
                             ├── Pulse Rumble / LED                  ├── Touch .minime/config/device_selected
                             ├── Update device.cfg                   └── Continue Boot to UI
                             └── Issue `reboot -f` (~2s cycle)
```

## Functional Requirements

1. **Trigger Condition**:
   - The selector activates on boot if `/mnt/sdcard/.minime/config/device_selected` does NOT exist and `AUTODETECT_SUPPORTED!=y`.

2. **Input Listening**:
   - Monitors `/dev/input/event*` for `KEY_UP`, `KEY_DOWN`, and `BTN_A` events.

3. **Haptic & Visual Feedback**:
   - On `KEY_UP` / `KEY_DOWN`: Pulses the vibration motor via GPIO/PWM (`/sys/class/pwm` or `/sys/class/gpio`) and blinks the status LED.

4. **DTB Cycling & Fast Reboot**:
   - On `KEY_UP` / `KEY_DOWN`: Increments/decrements candidate DTB index from `.minime/devices/*.dtb`.
   - Calls `device.sh set device <dtb_name>` to update `/mnt/sdcard/.minime/config/device.cfg`.
   - Executes `reboot -f` (or `kexec`) to re-enter bootloader/kernel within 2 seconds.

5. **Confirmation**:
   - When the correct DTB is loaded, the display panel initializes and renders the visual selection prompt ("Press A to confirm device").
   - On `BTN_A`: Writes `/mnt/sdcard/.minime/config/device_selected` marker and proceeds to standard boot without rebooting.

6. **Reset Mechanism**:
   - Setting `device=auto` or removing `device_selected` on FAT32 partition re-enables first-boot selector.

## Component Integration

- **[device.sh](file:///Users/ilembitov/Projects/minime/alpine/board/common/scripts/device.sh)**: Manages `device.cfg` reads/writes.
- **[traits.sh](file:///Users/ilembitov/Projects/minime/alpine/board/common/scripts/traits.sh)**: Reads active `/proc/device-tree/model` once DTB is locked.
- **Target Storage**: Configuration persisted in `/mnt/sdcard/.minime/config/device.cfg`.
