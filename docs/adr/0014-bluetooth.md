# Bluetooth Audio & Persistence

## Problem
Minime must support Bluetooth pairing and A2DP audio while keeping the userdata partition FAT32/exFAT-compatible. BlueZ stores adapter and device state in directories named with colon-separated MAC addresses (e.g. `A8:6E:4E:FA:69:8E`); FAT-compatible filesystems reject `:` in filenames, so the state cannot live directly on the userdata card.

## Solution
Use BlueZ and BlueALSA as the Bluetooth stack. Persist BlueZ state in a small ext2 filesystem image file (`/mnt/sdcard/.minime/config/bluetooth/state.fs`, 2 MB) inside the FAT userdata card. The Bluetooth OpenRC service loop-mounts it at `/var/lib/bluetooth`; it creates and formats the image on first use (`mkfs.ext2`, no journal) and rebuilds it if it is ever corrupt. Using a file rather than a partition means no reflash is required on existing cards. If the image cannot be mounted (no loop devices), the service falls back to a tmpfs + `storage.tar` snapshot.

For audio, adopt the native BlueALSA path (the same model NextUI uses): `audio.sh` rewrites `/run/asoundrc` so `pcm.!default` routes to the connected A2DP device via BlueALSA plug. The running emulator's SND layer (`workspace/all/common/api.c`) stats `/run/asoundrc` once a second (`SND_checkRoute`) and re-opens SDL audio against the new default (`SND_reopen`) — so the game's stream follows the route change within ~1s without any game cooperation. `keymon` owns the event detection: it watches the codec jack input device (`EV_SW`/`SW_HEADPHONE_INSERT`) for headphones and polls `bluetoothctl` for connected Audio Sinks, calling `audio.sh bt-on`/`bt-off` on state changes.

A mid-game disconnect is handled by the same route change: `keymon` detects the sink leaving, `audio.sh bt-off` restores the hardware route, and `SND_reopen` re-opens the game's audio against the speaker. This is the same trade-off NextUI accepts (no simultaneous speaker+BT output; a lost transport can stall SDL's close until the route change lands) and is the lowest-latency ALSA-only design available.

This replaces the earlier mirror design (`bt-mirror` + ALSA `file` FIFO) which kept the game pinned to the hardware PCM and mirrored audio to BlueALSA through a custom daemon. The mirror solved the same disconnect-freeze problem with a larger latency footprint and an extra component; the native route removes the daemon and the FIFO entirely.

## Examples
- State mount + persistence: `packages/components/boards/common/overlay/etc/init.d/bluetooth`
- ALSA route generation: `packages/components/boards/common/scripts/audio.sh`
- Route-change reopen: `workspace/all/common/api.c` (`SND_checkRoute`/`SND_reopen`)
- Event detection: `packages/ui/minui/workspace/minime/keymon/keymon.c`
- Trait-driven jack/power: `packages/ui/minui/workspace/minime/platform/traits.c`

## See Also
- Storage layout: [`0009-storage`](0009-storage.md)
- OTA behavior: [`0004-updates`](0004-updates.md)