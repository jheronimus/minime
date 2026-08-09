# 0015: YabaSanshiro libretro core — repository topology and merge workflow

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-09

---

## Context & Problem Statement

Minime needs a Sega Saturn libretro core. The only actively-developed Saturn
emulator is YabaSanshiro (fork of Yabause), whose standalone app ships regular
source releases. However:

- The original upstream repository (`devmiyax/yabause`) was **deleted from
  GitHub in 2026**. The final commit (`71c973f9`, v1.17.7, 2025-12-30) is
  preserved verbatim by the fork `Hengle/yabause`.
- Newer releases ship only as **GPL source tarballs** (e.g.
  `yabasanshiro-src-1.20.32.tar.gz`, 2026-08-02), with no git history.
- The in-tree libretro port is **ancient and broken**: it references core
  files that were renamed from `.c` to `.cpp` (`vdp1.c`, `vdp2.c`, `scsp.c`,
  `thr-linux.c`) and thus cannot compile against current releases. Upstream
  no longer maintains it (the author focuses on the Android/iOS app).

The old roadmap treated the upstream as a static, rarely-updated target and
modelled the fork as a "GooseStation builder" (patch-at-build-time). That
premise is obsolete: YabaSanshiro now releases frequently, and every release
is a source tarball. The project must be able to **absorb new releases
cheaply**, which constrains how much we are allowed to touch emulator code.

Reference models investigated:

- **GooseStation-builder**: pins an upstream commit, downloads a pristine
  tarball, and applies a 972 KB patch script at build time. Works only
  because DuckStation already ships an in-tree libretro target that it merely
  enables. Not a model for writing a port from scratch.
- **Ymir libretro port** (GitLab `libretro/emir`): keeps the emulator core
  upstream-shaped and unmodified; the port is a separate `apps/ymir-libretro`
  app over a library boundary, kept in sync by repeatedly merging upstream
  into a `libretro` branch.

## Decision

### 1. Fork repository topology (`jheronimus/yabause`, public)

Three branches, each with a distinct role:

| Branch | Content | Role |
|--------|---------|------|
| `upstream` | Pristine YabaSanshiro source tarballs, one snapshot per release | Read-only reference; updated by committing the next release's tarball contents |
| `main` | Pruned emulator core + our libretro glue | The actual port; what minime submodules at `src/yabause` |
| `archive` | v1.17.7 snapshot recovered via `Hengle/yabause` | Git-verifiable backup of the last upstream commit; kept read-only, no longer developed |

New upstream releases are committed to `upstream` **verbatim** (including
submodules, pinned to HEAD). `main` is regenerated from it.

### 2. `main` layout — upstream-shaped, pruned

`main` keeps upstream's `yabause/` directory layout. Pruning is done by
**deleting** what the libretro build does not need, never by restructuring:

- **Keep**: the emulator core files the libretro build compiles
  (`yabause/src/*.c/*.cpp`), their dependencies (`musashi/`,
  `sh2_dynarec_devmiyax/`, `titan/`, `gllibs/`), the Vulkan renderer sources
  (`yabause/src/vulkan/` minus the Windows-only prebuilt `lib/`), `shaders/`,
  and the libretro glue (`yabause/src/libretro/`).
- **Prune**: `android/`, `ios/`, `qt/`, `glfw/`, `gtk/`, `sdl/`, `cocoa/`,
  `webinterface/`, `retro_arena/`, `retroachievements/`, `runner/`,
  `test_framework.*`, `Makefile.dc`, `vulkan/lib/`, `win_template/`,
  `yabauseut/`, `snap/`, `.github/`, `appveyor.yml`, `Jenkinsfile`,
  `.travis.yml`.
- **`main` carries no git submodules.** Everything the standalone app links
  (eigen, oboe, rcheevos) belongs to Android/standalone features that are
  pruned.

### 3. Core-untouched policy

- **Emulator behavior files** (`vdp1.cpp`, `vdp2.cpp`, `scsp.cpp`, `memory.c`,
  `sh2core.c`, …) are kept **byte-identical to upstream**. The diff between
  `main` and `upstream` for these files must be empty.
- **Build/glue files may be edited freely**: `yabause/src/libretro/`
  (`libretro.c`, `Makefile`, `Makefile.common`) is *our* code, even though it
  lives in an upstream-shaped location. It is expected to diverge heavily
  from the dead upstream libretro glue.
- The libretro build (`Makefile.common`) must be maintained against the
  current core's filenames (e.g. the `.c`→`.cpp` renames).

### 4. Merge workflow (new YabaSanshiro release)

1. Download the new source tarball and commit its contents to `upstream`.
2. In `main`, copy the changed **core** files over from `upstream`; do not
   copy the dead libretro glue.
3. Re-apply the pruning (delete any newly-added Android/Qt/iOS/etc. files).
4. Update `libretro/Makefile.common` for any renamed/moved core files.
5. Verify the standalone libretro build; commit to `main`.

Because core files are byte-identical to upstream, step 2 is a mechanical
copy, and the diff review is limited to "what did the emulator change".

### 5. Initial `main` commit

`main` is (re)created as a **single initial commit** containing the pruned
core, the updated libretro glue (including the `.c`→`.cpp` Makefile.common
fix so the core builds out of the box), `LICENSE`/`COPYING`, `.gitignore`,
and the build files. No ROADMAP.md (see ADR 0016 scope; this file's history
is preserved in the fork's branches and `wip/main-original`).

## Consequences

- **Positive**: frequent upstream releases become cheap merges; core diff is
  reviewable; the libretro glue is unambiguously ours; no submodule
  dependency chain on `main`.
- **Negative**: emulator bug fixes cannot be applied as patches to core files
  (they must either be accepted upstream or implemented in the glue);
  pruning must be re-applied per release; the Vulkan renderer is retained as
  sources only (no prebuilt libs) pending the renderer ADR (0016).
- **Pruned-but-maybe-needed**: any pruned file can be re-added from
  `upstream` on demand — cost is a single merge commit.

## Alternatives considered

- **GooseStation-style build-time patching**: rejected because DuckStation's
  model relies on an existing in-tree libretro target, which YabaSanshiro
  does not have.
- **Physically restructured `core/` + `libretro/` trees**: rejected because it
  diverges from upstream paths, breaking the mechanical merge workflow.
- **Patch-based core edits**: rejected; violates the core-untouched policy
  and would conflict with every release.
