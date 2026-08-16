# ADR 0014: GPU Stack — Panfrost (Alpine) vs libmali/mali-kbase (Buildroot)

## Status
Accepted

## Context
All three supported SoCs embed ARM Mali Bifrost GPUs (H700: G31; RK3326: G31;
RK3566: G52). There are two ways to drive them:

1. **Open source**: the mainline Panfrost DRM driver + Mesa userspace
   (EGL/GLES/GBM over DRM/KMS).
2. **Proprietary**: ARM's Mali userspace (libmali) plus the out-of-tree
   mali-kbase kernel driver.

The two distro targets have different constraints: Alpine is musl and favors a
small, fully open toolchain; Buildroot is glibc and exists for compatibility
with closed-source software (libmali, DraStic, Pico-8). The GPU stack decision
is therefore made **per target**, not globally.

## Decision

### Alpine → Panfrost (open source)
- Kernel: `minime/boards/common/tiny-panfrost.config`
  (`CONFIG_DRM_PANFROST=y` + dependencies).
- Userspace: Mesa Panfrost via DRM/GBM/KMS provides GLES (`mesa-gles`),
  desktop OpenGL (`mesa-gl` ships `libGL.so.1`), EGL (`mesa-egl`), GBM
  (`mesa-gbm`), and a Vulkan driver (`mesa-vulkan-panfrost` / PanVK with
  `vulkan-loader`). libmali and mali-kbase are deliberately absent.
- `post-build.sh` injects `gpu_driver=panfrost` into
  `/usr/share/minime/traits/platform.ini`.

### Buildroot → libmali + mali-kbase (proprietary)
- Kernel: `minime/boards/common/tiny-libmali.config` — no in-tree GPU `=y`
  options; Panfrost is explicitly disabled; the out-of-tree mali-kbase module
  is built separately.
- Userspace: `src/libmali` blobs (Bifrost G31 for H700/RK3326, G52 for RK3566)
  provide EGL/GLES/GBM; `src/mali-kbase` is the out-of-tree kernel module.
  libmali is mutually exclusive with Mesa3D's Panfrost gallium driver.
- `post-build.sh` injects `gpu_driver=mali_kbase` into platform.ini.

### Shared contract
- The `gpu_driver` trait is written into `platform.ini` at build time and is
  the single source of truth for which driver is active. The shared
  `init.d/gpudriver` service reads it and loads the matching module (it
  replaced the separate panfrost/gpudriver scripts); `update.sh` uses it as
  the target-detection fallback (`panfrost=alpine`, `mali_kbase=buildroot`).
- udev rules (`minime/boards/common/overlay/etc/udev/rules.d/50-panfrost.rules`)
  set device permissions.

## Consequences
- Alpine ships a fully open GPU stack; Buildroot ships ARM's proprietary stack
  for closed-source compatibility (DraStic, Pico-8; YabaSanshiro's GL path
  there is deferred until the two-core split, see ADR 0023).
- Both targets surface GLES behind the single `gpu_driver` trait, so UIs
  (MinUI/Allium) need no per-target GPU knowledge.
- **Vulkan ships on Alpine only** (`vulkan-loader` + `mesa-vulkan-panfrost`);
  Buildroot/libmali ships no Vulkan driver. Whether YabaSanshiro's Vulkan
  renderer can actually drive Mali Bifrost via PanVK on the RK3566 is open
  research (see ADR 0023).

## Reference
- Kernel fragments: `minime/boards/common/tiny-panfrost.config`,
  `minime/boards/common/tiny-libmali.config`.
- Userspace: `src/libmali/`, `src/mali-kbase/`,
  `minime/targets/buildroot/external/package/{libmali,mali-kbase}/`.
- Alpine package lists: `minime/targets/alpine/configs/world-{common,h700,rk3326,rk3566}`.
- Injection: `minime/targets/{alpine,buildroot}/.../post-build.sh`.
- Related: `docs/adr/0023-yabasanshiro-libretro-port.md` (renderer strategy),
  `docs/adr/0018-cpu-performance-and-thermal-policy.md` (GPU thermal trips).
