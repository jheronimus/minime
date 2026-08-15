# ADR 0023: YabaSanshiro libretro core port

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10
* **Consolidates**: former `0015` (repository topology + merge workflow) and `0016` (renderer strategy)

---

## Context & Problem Statement

Minime needs a Sega Saturn libretro core. YabaSanshiro (a Yabause fork) is the
only actively developed Saturn emulator, but:

- The original repo (`devmiyax/yabause`) was **deleted from GitHub in 2026**;
  its final commit (`71c973f9`, v1.17.7) is preserved by `Hengle/yabause`.
- New releases ship only as **GPL source tarballs** (no git history).
- The in-tree libretro port is **ancient and broken** (`.c`→`.cpp` renames
  broke it); upstream no longer maintains it (the author focuses on the
  Android/iOS app).

Reference models: GooseStation's builder (patch-at-build-time) only works
because DuckStation ships an in-tree libretro target; the Ymir libretro port
(core kept upstream-shaped, port as a separate app layer) is the workable model.

## Decision

### 1. Fork topology (`jheronimus/yabause`)

- `upstream`: pristine source tarballs, one snapshot per release (read-only
  reference; updated by committing each new release verbatim).
- `main`: pruned emulator core + our libretro glue; what minime submodules at
  `src/yabause`. Regenerated from `upstream` on each release.
- `archive`: the v1.17.7 snapshot recovered via `Hengle/yabause` (read-only backup).

### 2. `main` is upstream-shaped and pruned

Keep the emulator core + deps (`musashi/`, `sh2_dynarec_devmiyax/`, `titan/`,
`gllibs/`), the Vulkan renderer **sources** (`src/vulkan/` minus the
Windows-only prebuilt `lib/`), `shaders/`, and our libretro glue
(`src/libretro/`). Prune the app shells (`android/`, `ios/`, `qt/`, `glfw/`,
`gtk/`, `sdl/`, `cocoa/`, ...) and CI files. **No git submodules on `main`.**
Pruned files can be re-added from `upstream` on demand.

### 3. Core-untouched policy

Emulator behavior files (`vdp1.cpp`, `vdp2.cpp`, `scsp.cpp`, `memory.c`,
`sh2core.c`, ...) stay **byte-identical to upstream** — the `main`/`upstream`
diff for these must be empty. Build/glue files (`src/libretro/`,
`Makefile.common`) are ours and free to diverge.

### 4. Merge workflow (new release)

Download the new source tarball → commit to `upstream` → copy the changed
**core** files into `main` → re-apply pruning → update `Makefile.common` for
renamed/moved files → build + commit. Because core files are byte-identical to
upstream, the merge is mechanical and reviewable.

### 5. Renderer: OpenGL ES 3.0 primary

The libretro core targets **OpenGL ES 3.0** (`RETRO_HW_CONTEXT_OPENGLES3` via
the `_OGLES3_` define path) — what minime's `libmali` provides, so no new GPU
userspace and the glue's video path is a repair, not a rewrite. The software
renderer (`vidsoft.c`) stays as a debug fallback (XRGB8888). **Vulkan is
retained as sources only** (prebuilt `lib/` pruned — x86/Windows only) and is
not the default: whether upstream's Vulkan renderer can target Mali Bifrost on
the RK3566 (driven by `mali-kbase`) is open research; if it pans out, a
follow-up ADR supersedes this one.

## Consequences

- Frequent upstream releases become cheap mechanical merges; core diffs are
  reviewable; the glue is unambiguously ours; no submodule chain on `main`.
- Emulator bug fixes cannot be patched into core files (must go upstream or
  into the glue); pruning is re-applied per release.
- Ships on current images (GLES userspace already present); raw Vulkan
  performance is left on the table pending the RK3566 investigation.
- Open work: implement `retro_get_memory_data` / `retro_get_memory_size`
  (currently stubs).

## Alternatives considered

- Build-time patching (GooseStation): rejected — no in-tree libretro target to
  enable.
- Restructured `core/` + `libretro/` trees: rejected — breaks the mechanical
  merge workflow.
- Vulkan or software as the default renderer: rejected (no Vulkan userspace or
  ARM prebuilt libs; software too slow for Saturn on RK3326/H700/RK3566).
