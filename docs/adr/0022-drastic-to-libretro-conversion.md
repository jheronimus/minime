# ADR 0022: DraStic Android Shared Library to Libretro Core Conversion

## Status
Accepted

## Context
DraStic 2.6.0.4a is a closed-source Nintendo DS emulator released as an ARM64 Android shared library (`libdrastic_arm64.so`). To run DraStic under MinUI and Allium on Minime Linux targets (Alpine musl & Buildroot glibc) via `minarch.elf`, DraStic must conform to the Libretro API specification (`libretro.h`).

## Decision

1. **Bionic Libc Compatibility Shim**
   - Implement `bionic_shim.c` to satisfy Android Bionic symbols: `__android_log_print`, `__android_log_write`, `android_set_abort_message`, `__errno`, and an 8-byte aligned `__sF` array mapping stdio streams.
   - Provide static GUID structures for OpenSLES interfaces (`SL_IID_ENGINE`, `SL_IID_PLAY`, `SL_IID_RECORD`, `SL_IID_VOLUME`, `SL_IID_BUFFERQUEUE`).
   - Implement Fortify string/memory wrappers (`__strcpy_chk`, `__strncpy_chk`, `__memcpy_chk`, `__memset_chk`).
   - Provide an `mprotect` wrapper to grant `PROT_READ | PROT_WRITE | PROT_EXEC` (W^X override) for DraStic's 62 MB ARM64 JIT code cache.

2. **JNI Environment & Virtual Filesystem Mock**
   - Provide a complete C implementation of `JNIEnv` and `JavaVM` matching standard JNI 1.6 table offsets.
   - Match `NativePathHandle` 64-bit ABI layout (`filePath` at offset 0, `fileName` at offset 8, `fileFd` at offset 16) so DraStic's native C code dereferences valid pointers.
   - Intercept `DraSticPathCache.open(path, mode)` to translate virtual paths to Linux POSIX file descriptors with fallback search paths (`/mnt/sdcard/Bios/NDS`, `/mnt/sdcard/Saves/NDS`, PAK directory).

3. **Libretro API Bridge**
   - Map DraStic JNI entry points (`JNI_OnLoad`, `onInit`, `startGame`, `updateFrame`, `renderFrame`, `updateInput`, `saveState`, `loadState`, `resetDS`, `quitSystem`) to standard Libretro functions (`retro_init`, `retro_load_game`, `retro_run`, `retro_serialize`, `retro_unserialize`).
   - Output `RETRO_PIXEL_FORMAT_RGB565` framebuffers supporting 3 display layout modes:
     - Vertical (256x384)
     - Single Screen (256x192 with L2 swap)
     - Side-by-Side (512x192)
   - Support 2 touch input modes: Physical touchscreen and Analog D-Pad pointer.

4. **Self-Contained External Repository**
   - Maintain the wrapper, build scripts, and packaging logic in `jheronimus/drastic` to keep main Minime and MinUI repositories clean and free from private submodule dependencies.

## Consequences
- Enables high-performance Nintendo DS emulation on RK3326, RK3566, and H700 handhelds under both Alpine musl and Buildroot glibc.
- MinUI launchers load DraStic via standard `minarch.elf` execution conventions without custom standalone binary hacks.
