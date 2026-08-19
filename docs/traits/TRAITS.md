# Minime Traits System

## Overview

Minime uses a deterministic, single-file trait registry per supported handheld device. The traits file is the single source of truth for all hardware capabilities, screen parameters, input paths, and audio/power quirks.

## Architecture & Lifecycle

1. **Registry**: Device definitions live in `packages/components/boards/<board>/traits/<device>.ini`.
2. **Build-Time Generation**: `packages/image/gentraits.sh` parses device INIs to produce runtime trait files and device tree overlays at image build time.
3. **Runtime Activation**: During early boot, OpenRC `init.d/traits` reads `/usr/share/minime/traits` and links the active device's traits to `/mnt/sdcard/.minime/traits`.
4. **Consumer Interface**: Launchers (MinUI, Allium, muOS), emulators, and tools (`remote`) read `/mnt/sdcard/.minime/traits` using the C reference reader (`docs/traits/traits.c` / `traits.h`).

## Schema Keys

| Key | Description | Example |
|---|---|---|
| `device` | Model identifier | `rg35xx-plus` |
| `board` | SoC family | `h700`, `rk3566`, `rk3326` |
| `screen_width`, `screen_height` | Physical LCD resolution | `640`, `480` |
| `screen_aspect` | Screen aspect ratio | `4:3`, `1:1`, `16:9` |
| `screen_rotation` | Userspace panel rotation (degrees) | `0`, `90`, `270` |
| `screen_type` | Panel technology | `ips`, `oled` |
| `input_type` | Controller interface | `keys`, `gpio`, `adc` |
| `has_analog_sticks` | Number of analog sticks | `0`, `1`, `2` |
| `battery_node` | Linux power supply sysfs path | `axp2202-battery` |
| `audio_dac` | ALSA sound card index / node | `0` |

## Reference Reader Implementation

A lightweight C parser (`traits.c` / `traits.h`) is provided in this directory:
- Zero external dependencies beyond standard libc.
- Reads `key=value` lines into an in-memory hashtable or struct.
- Provides fallback defaults when optional traits are omitted.

## See Also
- Trait evaluator: [`packages/image/gentraits.sh`](../../packages/image/gentraits.sh)
- OpenRC service: [`packages/components/boards/common/overlay/etc/init.d/traits`](../../packages/components/boards/common/overlay/etc/init.d/traits)
- Hardware definitions: [`packages/components/boards/`](../../packages/components/boards/)
