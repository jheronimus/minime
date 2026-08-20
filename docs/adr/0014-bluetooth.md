# Bluetooth Audio & Persistence

## Problem
Minime must support Bluetooth pairing and A2DP audio while keeping the userdata partition compatible with FAT32/exFAT. Bluetooth audio must also survive earbuds disconnecting during gameplay without freezing the emulator or losing speaker fallback.

BlueZ stores adapter and device state in directories named with colon-separated MAC addresses, such as `A8:6E:4E:FA:69:8E`. FAT-compatible filesystems reject `:` in filenames. BlueALSA PCM handles can also fail when an A2DP transport disappears while an emulator still owns the ALSA device.

## Solution
Use BlueZ and BlueALSA as the Bluetooth stack. Keep BlueZ's native runtime tree in `/var/lib/bluetooth`, and persist it as `/mnt/sdcard/.minime/config/bluetooth/storage.tar`. The Bluetooth OpenRC service extracts the archive at startup and recreates it at shutdown. This preserves the FAT32/exFAT userdata contract without encoding BlueZ's directory names.

Keep game audio on the hardware speaker PCM and mirror fixed-format audio through ALSA's `file` PCM to `/run/bt-audio.fifo`. The UI-agnostic `bt-mirror` helper keeps the FIFO reader open, drains it when no sink is connected, and feeds BlueALSA through `aplay` when an A2DP device is connected. `audio-monitor.sh` watches BlueZ, updates the target, and owns the connection transitions. `audio.sh` binds Bluetooth volume to the board's existing hardware mixer control through `softvol`.

These are deliberate compatibility adapters, not a new audio framework. PipeWire/PulseAudio and a native filesystem remain parked alternatives if the maintenance cost becomes unacceptable.

## Examples
- Bluetooth service and persistence: `packages/components/boards/common/overlay/etc/init.d/bluetooth`
- ALSA route generation: `packages/components/boards/common/scripts/audio.sh`
- Connection monitor: `packages/components/boards/common/scripts/audio-monitor.sh`
- Mirror helper: `src/bt-mirror/`
- Alpine package: `packages/components/alpine/aports/bt-mirror/`
- Buildroot package: `packages/components/buildroot/external/package/bt-mirror/`

## See Also
- Storage layout: [`0009-storage`](0009-storage.md)
- OTA behavior: [`0004-updates`](0004-updates.md)
