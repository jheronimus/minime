# 0026. Remote Diagnostics & Input Simulation Tool

## Context

Automated firmware testing and AI-driven pair-programming require live visual inspection of on-device rendering and automated keypress simulation. Previous custom firmware tools either depended on heavy UI-specific daemons, wrote temporary uncompressed BMPs directly to SD storage (causing flash wear and latency), or failed on modern DRM/KMS hardware rendering planes where `/dev/fb0` is bypassed by OpenGL/Vulkan/Panfrost.

## Decision

Implement a self-contained, firmware- and UI-agnostic C99 diagnostic tool (`/usr/bin/remote`) in `src/remote/`:

1. **Dual Display Capture Engines (`--backend auto|drm|fb`)**:
   - **DRM/KMS Engine (Default)**: Queries `/dev/dri/card0` CRTCs and primary hardware planes using `DRM_IOCTL_MODE_GETRESOURCES`, `DRM_IOCTL_MODE_GETCRTC`, and `DRM_IOCTL_MODE_GETPLANE`. Maps active framebuffers via dumb buffer offsets or `DRM_IOCTL_PRIME_HANDLE_TO_FD` (DMA-BUF). Captures live hardware-accelerated SDL2/Mesa/Panfrost frames without touching `/dev/fb0`.
   - **Legacy Framebuffer Fallback**: Directly memory-maps `/dev/fb0` for software-rendered targets or early boot stages.
   - **Auto Mode**: Probes DRM first; falls back to `/dev/fb0` if DRM has no active CRTC/plane.

2. **Inverse Display Rotation Matrix**:
   - Device traits define `screen_rotation` as the render angle applied to portrait panels.
   - The capture engine applies the inverse rotation `(360 - (screen_rotation % 360)) % 360` to restore raw panel scanout to the human player's upright landscape view.

3. **Zero-Disk-Write Streaming**:
   - Single-header PNG encoder (`stb_image_write.h`) compresses RGB24 frames entirely in RAM.
   - Outputs standard binary PNG to stdout or RFC 4648 Base64 strings for piping over Telnet/SSH with zero writes to device storage.

4. **Input Simulation via `/dev/uinput`**:
   - Registers a virtual Linux evdev gamepad (`Minime Remote Controller`).
   - Translates logical button names (`A`, `B`, `X`, `Y`, `UP`, `DOWN`, `LEFT`, `RIGHT`, `MENU`, `START`, `SELECT`, `POWER`, `VOL_UP`, `VOL_DOWN`) to hardware-specific keycodes resolved from `/mnt/sdcard/.minime/traits`.
   - Supports discrete press/release, combos, and timed macros (`UP:100,WAIT:200,A:50`).

## Status

Accepted.

## Consequences

- Automated test scripts and AI agents can capture live visual frames from both legacy framebuffer and modern Panfrost/KMS rendering pipelines.
- Flash storage is protected from write cycles during high-frequency diagnostic captures.
- Identical behavior across Alpine Linux (musl) and Buildroot (glibc).
