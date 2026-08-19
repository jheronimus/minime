# Shared RetroArch Emulator Cores

## Problem
Each UI launcher bundling its own emulator cores causes repository bloat, redundant compilation, version drift, and divergent patch sets across emulators.

## Solution
Consolidate emulator core recipes into `packages/cores/*/core.ini`. The central builder (`packages/cores/build.sh`) compiles all libretro `.so` binaries once per libc variant (`musl` or `glibc`) and outputs a shared archive consumed uniformly by MinUI, Allium, and muOS.

## Examples
- Core definition structure: `packages/cores/gambatte/core.ini`
- Local core build: `just build-cores`

## See Also
- Cores directory: [`packages/cores/`](../../packages/cores/)
- Core builder script: [`packages/cores/build.sh`](../../packages/cores/build.sh)
