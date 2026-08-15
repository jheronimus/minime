# ADR 0024: DraStic Android Shared Library to Libretro Core Conversion

## Status
Accepted — implementation in progress (video+audio work on-device; boot instability + minarch integration blocked)

## Context
DraStic 2.6.0.4a is a closed-source Nintendo DS emulator released as an ARM64 Android shared library (`libdrastic_arm64.so`). To run DraStic under MinUI and Allium on Minime Linux targets (Alpine musl & Buildroot glibc) via `minarch.elf`, DraStic must conform to the Libretro API (`libretro.h`).

## Decision
1. **Bionic shim** (`bionic_shim.c`): Android Bionic symbols (`__android_log_*`, `__errno`, `__sF`, Fortify `*_chk` wrappers), static OpenSLES GUIDs, and an `mprotect` W^X override for DraStic's 62 MB JIT cache.
2. **JNI + VFS mock** (`jni_mock.c`): a C `JNIEnv`/`JavaVM` matching JNI 1.6 table offsets; `NativePathHandle` matching DraStic's 64-bit ABI; `DraSticPathCache.open(path, mode)` translated to Linux fds with fallback search paths.
3. **Libretro bridge** (`drastic_libretro.c`): map JNI entry points to `retro_*`; RGB565 output with Vertical/Single/Side-by-Side layouts; touch + analog-cursor input. Audio via OpenSLES buffers → `retro_audio_sample_batch`.
4. **Self-contained external repo**: wrapper lives in `jheronimus/drastic` so Minime/MinUI stay free of the private core dependency.

## Consequences
- Enables NDS emulation on RK3326, RK3566, H700 under Alpine musl and Buildroot glibc.
- Launchers load DraStic via standard `minarch.elf` conventions.

## Implementation status (verified on the RK3566 ARC device)
- `retro_load_game` returns immediately — `startGame` (blocks until game exit) runs on a detached thread.
- SAVE_RAM backed by the core's battery file; `retro_serialize/unserialize` round-trip byte-identical (also gates rewind).
- **Video works**: `getScreenBuffers` → ARGB8888→RGB565, pushed via a custom SDL driver that rotates for the ARC's 90° panel and overlays an FPS/CPU/res HUD. Dropping the 10 ms post-`signalScreen` delay lifted frames to ~60+.
- **Audio works**: SDL audio device opens (44100 Hz stereo), core audio fed via `SDL_QueueAudio` (underruns during silent boot phases).
- The core boots to full emulation on-device (audio flows, frames pushed).

## Key findings (reverse engineering of `libdrastic_arm64.so`)
- **Frame presentation**: the emulation blocks on backpressure (`waitScreen`/`signalScreen` condvar pair) until the app signals a consumed frame; `signalScreen` must fire BEFORE `getScreenBuffers` (flips the render double-buffer), else frames are stale/black.
- **Padded ROMs crash**: DraStic allocates the ROM buffer from the header's declared size (offset 0x80) but CRCs the file size; padded ROMs (file > declared) overrun the buffer and the boot crashes. The mock patches the header size field to the file size on open (DraStic's `trim_roms` behavior).
- **Boot instability**: the game frequently sticks on the DS white boot screen (built-in firmware config not reliably applied) and intermittently crashes after ~30-60 s — a core-internal issue.
- **minarch integration blocker**: the boot does a fixed-address `munmap`+`mmap` of a scratch region; under minarch's memory layout the emulation thread collides with it, `mmap` returns elsewhere, and the NDS init calls `exit(-1)` → minarch exits 255. Confirmed via exit/mmap interposers; forcing MAP_FIXED boots but corrupts memory.
- The JNI table must match JNI 1.6 slot order exactly; `NativePathHandle` is `filePath@0, fileFd@8, fileName@16`.

## Remaining steps
1. Root-cause the boot instability (stuck white screen / intermittent crash) — likely the built-in firmware config or a core race.
2. Resolve the minarch fixed-mmap conflict (or ship the custom display driver).
3. Verify on-device audio + rotation; then MinUI integration (HUD, aspect ratio).
4. Ship: `NDS.pak/launch.sh` env exports, wrapper Makefile additions, distribution split (wrapper public / core private), Exophase permission.
