# ADR 0006: Libretro Core Builds Avoid Aggressive Optimization Flags

* **Status**: Accepted (bisect of the culprit flag pending)
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-05

---

## Context & Problem Statement

The minime platform branches in the MinUI fork were derived from upstream's `rgb30` (RK3566) core patches. For **pcsx_rearmed**, the rgb30 branch carries aggressive GCC performance flags on top of the neon GPU plugin:

```
CFLAGS   += -march=armv8-a+crc+simd
CFLAGS   += -fomit-frame-pointer -ffast-math -fdata-sections -ffunction-sections -fsingle-precision-constant -flto -fPIC -ftree-vectorize
LDFLAGS  += -flto -fPIC
OPTIMIZE += -Ofast -DNDEBUG=1
BUILTIN_GPU = neon
DYNAREC  = ari64
```

On-device testing (RG35XX Plus, Alpine/musl) showed **PSX menu and intro text stopped rendering** (Magic Castle): the 3D/intro content drew, but sprite/CLUT-based text was invisible. The **pre-branch build** (`platform=unix`, toolchain defaults, neon GPU + ari64 dynarec auto-selected) rendered text correctly. A/B on-device confirmed the flags are the cause: the conservative build renders text, the aggressive build does not.

Upstream MinUI ships the **same broken rgb30 config** (the flags have been present since the initial rgb30 work, commits `0701138`/`f7072dc`); no upstream issue reports it. We verified pcsx_rearmed is otherwise current (pin `99d2ce02`, one commit behind upstream HEAD).

## Decision

The `minime` platform branch for **pcsx_rearmed** is:

```
else ifeq ($(platform), minime)
   TARGET := $(TARGET_NAME)_libretro.so
   CC = $(CROSS_COMPILE)gcc
   CXX = $(CROSS_COMPILE)g++
   AR = $(CROSS_COMPILE)ar
   ARCH = arm64
   DYNAREC = ari64
```

i.e. **neon GPU + ari64 dynarec with the toolchain's default optimization**, deliberately omitting the rgb30 aggressive flags (`-Ofast`, `-flto`, `-ftree-vectorize`, `-ffast-math`, `-fsingle-precision-constant`, `-fdata-sections`, `-ffunction-sections`). This is a documented deviation from upstream rgb30's config, justified by direct on-device evidence. The neon GPU and ari64 dynarec (the performance-critical runtime pieces) are preserved.

## Consequences

- **PSX text renders correctly** on all boards (verified on-device).
- **Performance**: the conservative build relies on the neon GPU + ari64 dynarec for hot paths; the dropped flags were compile-time tuning. Measurable regression risk is low but not yet benchmarked.
- **Pending bisect**: the single culprit flag is not yet identified. Suspects: `-Ofast` (implies unsafe float semantics), `-flto` (cross-TU), `-ftree-vectorize` (auto-SIMD over hand-written NEON). Likely-safe and candidate to restore: `-ffast-math` (used by upstream's own `CortexA73_G12B` branch and by our working picodrive branch), `-fsingle-precision-constant`, `-fdata-sections`, `-ffunction-sections`, `-march=armv8-a+crc+simd`. Restore any confirmed-safe flags after a one-round on-device A/B.
- **At-risk cores**: three other minime branches inherited the same aggressive-flag pattern and are the same risk class (unconfirmed): `mgba` (`-Ofast -flto -ftree-vectorize`), `mednafen_vb` (`-flto`), `mednafen_supafaust` (`-Ofast -flto=4 -fwhole-program`). Apply the same conservative fix if any shows graphics/text issues.
- **Not the cause**: the upstream "slow linked list processing" hack (`pcsx_rearmed_gpu_slow_llists`, libretro/pcsx_rearmed#478) fixes a separate game-side DMA bug class; it does not explain the flag-induced regression.

---

## Reference

- Fix commit: `minime/ui/minui` fork `8705ef9` (minime submodule `f903d5cf`).
- Upstream rgb30 pcsx branch: `workspace/rgb30/cores/patches/pcsx_rearmed.patch`.
- Issue class (not the cause): libretro/pcsx_rearmed#478 "Pause Menu doesn't show texts".
- Related single-binary ISA decision: `docs/adr/0005-single-binary-cpu-isa.md` (covers `-march`/`-mtune`, a different flag set).
