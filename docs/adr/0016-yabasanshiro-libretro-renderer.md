# 0016: YabaSanshiro libretro core — video renderer strategy

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-09

---

## Context & Problem Statement

The YabaSanshiro libretro core (ADR 0015) must pick a video output path. The
emulator ships several renderers, and the choice drives both on-device
performance and how much of the core must be ported:

- **OpenGL / OpenGL ES**: the standalone build still supports this
  (`YAB_WANT_OPENGL` defaults ON; compiles with `-D_OGLES3_` and links
  `EGL GLESv2`). The dead libretro glue already targets GLES3
  (`RETRO_HW_CONTEXT_OPENGLES3`).
- **Software**: `vidsoft.c` is present and functional.
- **Vulkan**: upstream's modern renderer (VDP1 compute rasterizer, VDP2
  compositor, G-buffer) is scoped to `YAB_PORTS=vulkan` (the Android build
  model). The only prebuilt Vulkan libs shipped are x86/x86_64 Windows
  `.lib` files; on Linux/Android the build uses the system Vulkan loader or
  the Android NDK shaderc. The maintainer is focused on the Android app.

Minime's on-device targets (RK3326, H700, RK3566) use Mali GPUs driven by
`libmali` (minime's GPU userspace, see `src/libmali`). Today minime ships the
**OpenGL ES** userspace; there is no Vulkan userspace in the image. The
flagship target (RK3566, RG ARC-D) is where Saturn performance matters most.

## Decision

### 1. Primary on-device path: OpenGL ES 3.0

The libretro core targets **OpenGL ES 3.0** as the on-device renderer:

- It is what minime's `libmali` provides today — no new GPU userspace needed
  to ship the core.
- The dead libretro glue already requests `RETRO_HW_CONTEXT_OPENGLES3`, so
  the video plumbing is a repair job, not a rewrite.
- Upstream still compiles this path, so the core can stay upstream-faithful
  rather than carrying an out-of-tree renderer.

The software renderer (`vidsoft.c`) remains available as a fallback/debug
path (e.g. when a GLES context is unavailable), matching the old glue's
`VIDSOFT` entry.

### 2. Vulkan: retained as sources, investigated, not default

- `yabause/src/vulkan/` **sources are kept** on `main` (ADR 0015) so the
  renderer is available for evaluation without a re-merge.
- The Windows-only prebuilt `vulkan/lib/` is **pruned**; it is unusable for
  aarch64 Linux and is the bulk of the tarball size.
- Vulkan is **not** the default path. Whether it can become one is an open
  question gated on two pieces of research:
  1. Whether upstream's Vulkan renderer can target the Mali Bifrost GPUs in
     the RK3566 (which minime's `mali-kbase` driver drives).
  2. How Rocknix/ArkOS added Vulkan userspace for the RK3566 — the
     investigation target, since Ark is the main intended host for the
     Saturn core.
- If a future release provides an ARM-capable Vulkan path, a follow-up ADR
  supersedes this one.

### 3. libretro hardware context

The core requests a libretro HW render context (`RETRO_HW_CONTEXT_OPENGLES3`
via the existing `_OGLES3_` define path). The software path falls back to
normal `retro_video_refresh_t` with XRGB8888 (as the old glue's `VIDSOFT`
entry does).

## Consequences

- **Positive**: ships on current minime images with no new GPU userspace;
  the renderer repair is limited to the glue; Vulkan stays available as a
  source-level option for the Ark/RK3566 investigation.
- **Negative**: OpenGL ES leaves raw Vulkan performance on the table if the
  RK3566 Vulkan investigation pans out; the software path is likely too slow
  for full-speed Saturn on these SoCs and is a fallback only.
- **Open work**: implement `retro_get_memory_data`/`retro_get_memory_size`
  (currently stubs) for RetroAchievements via the libretro ABI; investigate
  Vulkan on RK3566 (Rocknix) as a follow-up.

## Alternatives considered

- **Vulkan as default**: rejected for now — no Vulkan userspace in minime,
  no ARM prebuilt libs, and the porting cost is high.
- **Software as default**: rejected — insufficient performance for Saturn on
  RK3326/H700/RK3566; kept only as a debug fallback.
