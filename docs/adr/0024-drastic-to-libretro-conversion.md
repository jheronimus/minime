# ADR 0024: DraStic Android Shared Library to Libretro Core Conversion

## Status
Accepted — implementation in progress (wrapper functional; core render path blocked)

## Context
DraStic 2.6.0.4a is a closed-source Nintendo DS emulator released as an ARM64 Android shared library (`libdrastic_arm64.so`). To run DraStic under MinUI and Allium on Minime Linux targets (Alpine musl & Buildroot glibc) via `minarch.elf`, DraStic must conform to the Libretro API (`libretro.h`).

## Decision
1. **Bionic shim** (`bionic_shim.c`): Android Bionic symbols (`__android_log_*`, `__errno`, `__sF`, Fortify `*_chk` wrappers), static OpenSLES GUIDs, and an `mprotect` W^X override for DraStic's 62 MB JIT cache.
2. **JNI + VFS mock** (`jni_mock.c`): a C `JNIEnv`/`JavaVM` matching JNI 1.6 table offsets; `NativePathHandle` matching DraStic's 64-bit ABI; `DraSticPathCache.open(path, mode)` translated to Linux fds with fallback search paths (`/mnt/sdcard/Bios/NDS`, `/mnt/sdcard/Saves/NDS`, PAK dir).
3. **Libretro bridge** (`drastic_libretro.c`): map JNI entry points (`JNI_OnLoad`, `onInit`, `startGame`, `updateFrame`, `renderFrame`, `updateInput`, `saveState`, `loadState`, `resetDS`, `quitSystem`) to `retro_init/load_game/run/serialize/unserialize`; RGB565 output with Vertical (256x384) / Single (256x192) / Side-by-Side (512x192) layouts; physical-touch and analog-cursor input.
4. **Self-contained external repo**: wrapper lives in `jheronimus/drastic` so Minime/MinUI stay free of the private core dependency.

## Consequences
- Enables NDS emulation on RK3326, RK3566, H700 under Alpine musl and Buildroot glibc.
- Launchers load DraStic via standard `minarch.elf` conventions, no standalone hacks.

## Implementation status (verified on qemu-aarch64 and the RK3566 device)
- `retro_load_game` returns immediately — `startGame` (blocks until game exit) runs on a detached thread, matching minarch's load→run flow.
- SAVE_RAM (`retro_get_memory_data/size`) backed by the core's battery file `User/backup/dseins.dsv` (mmap'd, seeded from minarch's `.sav`), coherent with the core's reads/writes.
- `retro_serialize/unserialize` via the core's `_savestate_temp.dss`; round-trip verified byte-identical (also gates rewind).
- Audio: OpenSLES buffers → `retro_audio_sample_batch` (44100 Hz stereo, real-time), gated on the first audio buffer.
- Video: `getScreenBuffers` → ARGB8888→RGB565 → `video_cb` (256×384), gated on the core's frame counter so the wrapper never races boot.
- The core boots to full emulation on the device (audio flows, `dseins.dsv` created, frames pushed).

## Key findings (reverse engineering of `libdrastic_arm64.so`)
- The JNI table must match JNI 1.6 slot order exactly; the first version was missing 5 fields (MonitorEnter..GetStringUTFRegion), shifting `GetPrimitiveArrayCritical` so the core's `env[222]` read past the table.
- Signatures differ from Android docs: `saveState`/`loadState` take `(slot[,async])` not a path; `updateFrame`/`updateInput` pack touch as `(x<<16)|y`; `renderFrame` is `(x,y,mode)` — the GL upload path.
- `NativePathHandle` is `filePath@0, fileFd@8, fileName@16`, not `fileFd@16`. The old layout only worked under qemu by accident (a heap pointer with bit31 set made the core fall back to `fopen(path)`); on the RK3566 it caused `fdopen(garbage)` → EBADF → `exit(255)`, killing minarch.
- The boot intermittently crashes (~40-50%) in a CRC overrun on a garbage ROM-data size — a core-internal race, reproduced identically under qemu and on device with an inert `retro_run`.
- Video is black: `getScreenBuffers` returns the double-buffer's stale side; the emulation writes `buffer[1-current]` and the swap only happens on a presentation call not yet located. The frame counter is pinned at `0xa` (~10 frames, then blocked on backpressure).
- `dseins.nds` is homebrew (HOMEBREW/####), so R4/DLDI SD emulation is in play.

## Remaining steps
1. Find/drive the frame-presentation call that flips the render double-buffer (or force software rendering via the core's obfuscated-key config) — unblocks video.
2. Mitigate/root-cause the intermittent boot CRC crash (launcher retry-on-crash is the pragmatic fallback).
3. Verify audio through the device speakers (minarch SND_init→ALSA has an intermittent teardown race).
4. Ship: `NDS.pak/launch.sh` env exports, wrapper Makefile additions, distribution split (wrapper public / core private), Exophase permission.
