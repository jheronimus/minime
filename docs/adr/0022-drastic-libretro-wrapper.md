# ADR 0022: DraStic Libretro Wrapper & Bionic Shim

## Context

DraStic is a closed-source Nintendo DS emulator for ARM hardware.
The Android release contains `libdrastic_arm64.so` (native AArch64 ARM64 JIT core) export signatures under the JNI API (`Java_com_dsemu_drastic_DraSticJNI_*`).

MinUI uses `minarch.elf` as a Libretro frontend requiring `_libretro.so` cores using software RGB565 framebuffers.

## Decisions

1. **Architecture Target**: Target ARM64 (`AArch64`) exclusively using `libdrastic_arm64.so`.
2. **Libretro Wrapper (`drastic_libretro.so`)**:
   - Implements standard Libretro API (`retro_init`, `retro_run`, `retro_load_game`, `retro_serialize`, `retro_unserialize`).
   - Maps Libretro video callbacks to 16-bit `RETRO_PIXEL_FORMAT_RGB565` software framebuffers.
   - Registers core options (`RETRO_ENVIRONMENT_SET_VARIABLES`) and key descriptors (`RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS`).
3. **Bionic Compatibility Shim (`bionic_shim.c`)**:
   - Provides minimal stubs for Android Bionic APIs (`__android_log_print`, `libOpenSLES.so` audio hooks).
   - Compatible with both `musl` (Alpine) and `glibc` (Buildroot).
4. **Mock JNI Environment (`jni_mock.c`)**:
   - Constructs a static `JNIEnv` function pointer table simulating Java Native Interface calls required by `libdrastic_arm64.so`.
5. **Display & Input Processing**:
   - Supports 3 screen layout modes: Vertical (256x384), Single screen with swap, and Side-by-side (512x192).
   - Supports 3 touchscreen modes: Direct physical touch, Analog stick cursor, and D-pad pointer mode (`Select+L1` toggle).

## Consequences

- Native 64-bit performance on ARM64 platforms (RK3566, H700, RK3326).
- Zero overhead on JIT execution path.
- Works inside MinUI `minarch.elf` as `NDS.pak`.
