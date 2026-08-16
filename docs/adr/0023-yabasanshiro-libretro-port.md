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

### 5. Renderer: software (Titan) default, GL retained

Both Minime frontends — minarch (RGB565 only) and Allium (RGB565/XRGB8888) —
accept only software frames and expose no hardware-render context, so the
**software renderer (`vidsoft.c`, the Titan pipeline) is the Minime default**.
The glue requests an OpenGL HW context and falls back to software when the
frontend refuses it (which both Minime UIs always do); the glue converts to
the frontend's pixel format.

The OpenGL renderer stays **compiled in** (it is upstream's default and the
only path that uses upstream's shaders): on Alpine it links against Mesa's
desktop `libGL` (`mesa-gl`, see ADR 0014). On **Buildroot**, libmali ships no
`libGL`, so the GL-linked core does not build there yet — the core is
`optional=1` in the shared manifest, so Buildroot images ship without a Saturn
core until a two-core split (GL vs software-only) lands.

**Vulkan is retained as sources only** (prebuilt `lib/` pruned — x86/Windows
only) and is not the default. On Alpine, PanVK (`mesa-vulkan-panfrost`)
provides a driver, so whether upstream's Vulkan renderer can target Mali
Bifrost on the RK3566 is testable there; Buildroot has no Vulkan path. If
Vulkan pans out, a follow-up ADR supersedes this one.

## Consequences

- Frequent upstream releases become cheap mechanical merges; core diffs are
  reviewable; the glue is unambiguously ours; no submodule chain on `main`.
- Emulator bug fixes cannot be patched into core files (must go upstream or
  into the glue); pruning is re-applied per release.
- Software rendering needs no on-device GL and works under both Minime
  frontends; the GL path stays available for GL-capable frontends
  (RetroArch) and for the deferred frontend-GL work (GLSM/hardware contexts
  in minarch/Allium).
- Known gap: Buildroot images ship no Saturn core until the two-core split.
- Port completion is tracked in the glue (`src/libretro/`); the remaining
  open work covers save-RAM exposure, savestates, CD format coverage, BIOS
  handling, and MinUI/Allium system wiring.

## Alternatives considered

- Build-time patching (GooseStation): rejected — no in-tree libretro target to
  enable.
- Restructured `core/` + `libretro/` trees: rejected — breaks the mechanical
  merge workflow.
- Vulkan or software as the default renderer: rejected (no Vulkan userspace or
  ARM prebuilt libs; software too slow for Saturn on RK3326/H700/RK3566).
