# Build Infrastructure & Pipeline

## Problem
Building multiple Linux distributions across 3 SoC families (H700, RK3326, RK3566) and 3 UI launchers (MinUI, Allium, muOS) requires excessive CI turnaround time and risks polluting host environments during local builds.

## Solution
Use a parameter-driven GitHub Actions matrix pipeline powered by containerized runners (`minime-musl` and `minime-glibc`). The pipeline builds bootloaders, emulator cores, UI binaries, and OS components as modular stages. Ephemeral UI and core archives are passed as run artifacts. Local validation is enforced instantly via `just validate-static` git hooks.

## Examples
- Single target CI dispatch: `gh workflow run build.yml -f libc=alpine -f soc=rk3566 -f ui=minui`
- Local static validation: `just validate-static`

## See Also
- Build workflow: [`.github/workflows/build.yml`](../../.github/workflows/build.yml)
- Local quality gates: [`Justfile`](../../Justfile)
