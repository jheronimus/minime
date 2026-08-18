# ADR 0022: Shared RetroArch Core Build

## Status

Accepted

## Context

MinUI and Allium both need RetroArch cores, but built them differently:

- **MinUI** cloned and compiled 13 cores inside its submodule build
  (`workspace/minime/cores/`), each patched with a `platform=minime` branch.
- **Allium** built zero cores; it shipped ~100 committed stock cores in
  `static/RetroArch/.retroarch/cores/` and its RetroArch wrapper loads
  `-L RetroArch/.retroarch/cores/<name>_libretro.so`.

This duplicated build logic, let the two UIs drift, and made Allium's shipped
cores unverifiable.

## Decision

Build every core **once** in CI and let both UIs consume the flat output.

1. **`minime/build/cores/` is the single source of truth** (moved out of the
   MinUI submodule):
   - `manifest`: 25 recipes in `core|repo|hash|buildpath|makefile|flags|patch|
     platform|core_so|optional|autobump|builder` form. The 13 original MinUI
     cores plus handy (Lynx), mednafen_wswan (WonderSwan), yabasanshiro
     (Saturn, WIP) and drastic (NDS, WIP, glibc-only) from jheronimus forks,
     and the 2026-08 review set (snes9x, genesis_plus_gx, mednafen_ngp, fbneo,
     flycast, mupen64plus_next, ppsspp) — see
     `docs/research/cores-review.md`. `builder` selects the build system:
     `make` (default) or `cmake` (flycast, ppsspp, the GLES3 big-three are
     `optional=1` and need a GL host, see ADR 0023).
   - `patches/`: the 13 vendored `platform=minime` patches, the 2 extra
     per-core patches gambatte/pokemini carried over from the old build, and
     new handy + mednafen_wswan patches. Applied in order with `git apply -p1`
     (a core's `patch` field may list several, space-separated).
   - `buildcores.sh`: clones, patches and builds every recipe, emitting a flat
     `out/` dir of `<name>_libretro.so` (+ drastic `lib*.so` shims) and
     `cores.txt`.
2. **`build-cores` CI job** (matrix musl/glibc, mirrors `build-ui`) runs
   `buildcores.sh` in the `minime-musl` / `minime-glibc` containers, caches
   `minime/build/cores/out` and a per-libc ccache, and uploads a `cores-<libc>`
   artifact. `build-ui` depends on it and downloads the artifact to
   `minime/build/cores/out`.
3. **Consumption**:
   - MinUI: the submodule `cores:` make target copies the flat artifact into
     `SYSTEM/minime/cores` (all paks load `$CORES_PATH/<EMU_EXE>_libretro.so`
     from there). The in-submodule core build was deleted; all emulator paks
     moved to base SYSTEM and LYNX/WS/SAT/NDS paks were added.
   - Allium: `mkui.sh` copies the artifact `.so` files into
     `RetroArch/.retroarch/cores/`, overwriting the committed stock cores.
4. **Autobump**: `update-cores.yml` (cron + `repository_dispatch`) bumps
   `autobump=1` pins in the manifest via `git ls-remote`. `autobump=0`
   stays pinned forever: mgba (CMake-migrated upstream) and WIP
   drastic/yabasanshiro.

## Consequences

- One build, one toolchain, zero Makefile drift between UIs; the shared
  `-march=armv8-a+crc -ffast-math` baseline (ADR 0005/0006) is applied to every
  core in both UIs.
- CI is green even while drastic/yabasanshiro are incomplete (`optional=1`).
- Pinned cores with unapplying patches fail loudly and are caught by
  `check-patches.sh` + the build-cores job.
- Submodule UI builds no longer compile cores; UI build time drops accordingly.

## References

- ADR 0005/0006: single-binary CPU ISA and core build optimization flags.
- ADR 0004: target build convention (this ADR covers UI cores, not target
  rootfs; `buildcores.sh` is a separate `minime/build/` component).
- ADR 0023 (yabasanshiro port) and ADR 0024 (drastic conversion) describe the
  two WIP cores.
