# ADR 0024: DraStic Android Shared Library to Libretro Core Conversion

## Status

Accepted — implementation in progress. Video + audio verified on-device; boot
instability and the minarch fixed-mmap conflict remain blocked. A native-Linux
DraStic alternative was investigated and **rejected** (does not meet the core
requirement: a MinUI-friendly libretro core that is libc-agnostic).

## Context

DraStic 2.6.0.4a is a closed-source NDS emulator released as an ARM64 Android
shared library (`libdrastic_arm64.so`, 74 exported JNI symbols). To run it under
MinUI/Allium via `minarch.elf` on both Minime targets (Alpine musl & Buildroot
glibc) it must conform to the Libretro API.

## Decision

Wrap `libdrastic_arm64.so` in a self-contained external wrapper
(`jheronimus/drastic`, kept out of Minime/MinUI):
1. **Bionic shim** — Android Bionic symbols (`__android_log_*`, `__errno`,
   `__sF`, Fortify `*_chk`), static OpenSLES GUIDs, `mprotect` W^X override for
   the 62 MB JIT cache.
2. **JNI + VFS mock** — C `JNIEnv`/`JavaVM` at JNI 1.6 offsets;
   `NativePathHandle` (`filePath@0, fileFd@8, fileName@16`); DraSticPathCache
   open → Linux fd.
3. **Libretro bridge** — JNI entries → `retro_*`; RGB565 with
   Vertical/Single/Side-by-Side layouts; touch + analog-cursor; OpenSLES audio
   buffers → `retro_audio_sample_batch`.
4. **External repo** so Minime/MinUI stay free of the private core.

## Implementation status (verified on the RK3566 ARC device)

- `retro_load_game` returns immediately; `startGame` (blocks until game exit)
  runs on a detached thread.
- SAVE_RAM backed by the core's battery file; serialize/unserialize
  round-trip byte-identical.
- **Video works**: `getScreenBuffers` → ARGB8888→RGB565 via a custom SDL driver
  that rotates for the ARC's 90° panel + FPS/CPU/res HUD. Dropping the 10 ms
  post-`signalScreen` delay lifted frames to ~60+.
- **Audio works**: SDL audio (44100 Hz stereo) fed via `SDL_QueueAudio`.
- Core boots to full emulation on-device (audio flows, frames pushed).

## Key findings (reverse engineering)

- **Frame presentation**: emulation blocks on the `waitScreen`/`signalScreen`
  condvar pair; `signalScreen` must fire BEFORE `getScreenBuffers` (flips the
  render double-buffer), else frames are stale/black.
- **Padded ROMs crash**: ROM buffer is allocated from the header size (0x80)
  but CRC'd from file size; the mock patches the header size to file size.
- **Boot instability**: game often sticks on the white boot screen (built-in
  firmware config not reliably applied) and intermittently crashes after
  ~30-60 s — core-internal.
- **minarch integration blocker**: boot does a fixed-address `munmap`+`mmap` of
  a scratch region; under minarch's layout the emulation thread collides,
  `mmap` returns elsewhere, and NDS init calls `exit(-1)` → minarch exits 255.
  Forcing `MAP_FIXED` boots but corrupts memory.
- JNI table must match JNI 1.6 slot order exactly.

## Native-Linux alternative evaluated and rejected

`trngaje/advanced_drastic` ships the official Linux DraStic binary
(`drastic_v2522`, aarch64 glibc, ELF PIE) plus a per-platform `libadvdrastic.so`
(LD_PRELOAD hook that intercepts DraStic video via `dlsym`). Verified on
rk3566/rk3326/h700 by Rocknix/muOS/ArkOS.

Rejected because it cannot meet the core requirement (a libretro core that is
libc-agnostic):
- **Not a library**: `drastic_v2522` exports **0** dynamic symbols (vs 74 for
  the Android `.so`). It can only be hosted as a standalone app via an exec
  wrapper — video/audio/input/saves then go through DraStic's own SDL app, not
  minarch. Not a real libretro core.
- **glibc-only**: needs glibc ≥ 2.27 (binary) / ≥ 2.38 (hook). Alpine (musl)
  cannot load it; a bundled-glibc hack is fragile and ~20 MB.
- Closed-source hook would be used as-is (rejected by project).

## Remaining steps (the two live paths)

1. **Fix the wrapper's two bugs** (keeps the libc-agnostic libretro core):
   - *mmap conflict*: shim `mmap` in the wrapper and pre-reserve DraStic's
     fixed scratch region (`PROT_NONE` at the exact address) before the core
     boots, so its `munmap`+`mmap` lands correctly. Test on-device (ARC).
   - *boot instability*: pre-seed the firmware config (`drastic.cfg` /
     firmware settings) the core expects at boot.
2. **If intractable, adopt melonDS**: open-source libretro core, builds for
   musl + glibc, already MinUI-native; trades performance on RK3326/RK3566.

Ship steps after unblocking: MinUI `NDS.pak/launch.sh` env exports, wrapper
Makefile additions, distribution split, Exophase permission.
