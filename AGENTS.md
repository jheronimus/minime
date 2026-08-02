# Minime (Custom Linux/Buildroot firmware)

Minime is a basic custom firmware for Anbernic handhelds (RK3326/H700/RK3566).

## Goals

- Fast to build and test. Builds completely on Github Actions in under 30 minutes per image.
- Wide compatibility. Comes in two versions: Alpine (smaller, faster to build), Buildroot (glibc, so compatible with closed source software like libmali, Drastic, Pico-8).
- Automates as much as possible: tests, quality gates, builds, release process.
- Strict separation between firmware and UI. Implements a trait system and a UI contract that makes it easy to add Minime support to existing projects (currently Allium and MinUI support Minime).
- Clean modular architecture.


## What's included

Only the basic components required by launchers: alsa, wpa_supplicant, bluez, telnet, ftp, GPU drivers, etc.

## Monorepo Structure

- `minime/`: Central source of truth for hardware definitions, bootloaders, target software builders, and image packaging.
  - `boards/`: Board definitions, DTS, kernel patches, traits, and OpenRC overlays.
    - `common/`: Shared OpenRC services (`overlay/etc/init.d/`), sysctl, wifi config, `device.sh`.
    - `h700/`, `rk3326/`, `rk3566/`: Per-board DTS, patches, traits, `boot.env`, and `genimage.cfg`.
  - `uboot/`: U-Boot configs (`config/`), patches (`patches/`), and prebuilt binaries (`out/`).
  - `targets/`: Target software builders.
    - `alpine/`: Core Alpine target build system (`aports/`, `configs/`, `container/`, `Makefile`, `build.sh`).
    - `buildroot/`: Core Buildroot target build system (`external/`, `Makefile`).
  - `build/`: Centralized image assembly (`mkimage.sh`), update package generation (`mkupdate.sh`), and UI assets (`genassets.sh`).
- docs/: Documentation, ADRs (adr/), and specs/research (research/).
- `src/`: Shared source code (libmali GPU userspace, mali-kbase kernel driver).
  - `mali-kbase/`: ARM Mali Bifrost kernel driver source (out-of-tree module).
  - `libmali/`: ARM Mali userspace driver source + proprietary blobs.
- `roms/`: Preloaded ROMs package.

## File Locations & Repository Mapping

Minime supports two build targets: Alpine and Buildroot, housed under `minime/targets/`. All shared configuration files, DTS/DTB files, kernel patches, firmware blobs, and hardware traits live in the central `minime/boards/` directory. Target build scripts reference or import them directly from there.

For precise paths, consult [docs/MAP.md](file:///Users/ilembitov/Projects/minime/docs/MAP.md).

For init scripts, `minime/boards/common/overlay/etc/init.d/` is the single source of truth for cross-distro OpenRC services. At build time, target builders copy these init scripts into their rootfs before building `system.erofs`.

## Local Target Builds

Alpine and Buildroot targets are built from their respective directories in `minime/targets/` using the two-step build convention:
- **Alpine**: `make -C minime/targets/alpine components BOARD=<board>` then `make -C minime/targets/alpine image BOARD=<board>`
- **Buildroot**: `make -C minime/targets/buildroot components BOARD=<board>` then `make -C minime/targets/buildroot image BOARD=<board>`

### Build Convention

Both targets follow the same pattern:
```
make components  →  build.sh  (compilation in container)
make image       →  genassets.sh + mkimage.sh + mkupdate.sh  (packaging in shared container)
```

**Rules:**
- `build.sh` does compilation only. No image packaging (no genimage, no mcopy, no mkdosfs).
- `mkimage.sh` does image packaging only. No compilation (no make, no gcc, no kernel build).
- `mkupdate.sh` does update archive generation only.
- `genassets.sh` does UI asset retrieval and extraction only.
- The Makefile orchestrates the two steps. CI calls `make components` then `make image` separately.
- Never add compilation logic to `mkimage.sh` or `mkupdate.sh`.
- Never add packaging logic to `build.sh`.

## Agent Directives

- **No Manual Workflow Dispatch**: Every push to `main` filtered to `minime/**` automatically triggers `build.yml`, which builds bootloaders, UIs, and OS images in one pipeline. **Never** use `gh workflow run` to manually dispatch `build.yml` — this causes concurrent runs that corrupt the `testing` release assets.
- **Cancel Stale Jobs**: If you have made several pushes in succession, run `gh run list` and cancel any in-progress or queued `build.yml` runs from earlier pushes — only the latest commit matters. Never allow more than one `build.yml` run to be active concurrently.
- **Architecture & Optimization Knowledge**: Store all architectural decisions, filesystem/kernel performance optimizations, and design rationale in Architecture Decision Records under `docs/adr/` (e.g. `docs/adr/0001-fat32-cluster-and-image-sizing.md`).
- **No Temporary Workarounds**: Fix local/runner states directly in the environment. Never add temporary configs, scripts, or hooks to build logic.
- **Path and Restructuring Integrity**: When moving, renaming, or consolidating files or directories (e.g., board assets, source paths, packages), you MUST perform a repository-wide search (`grep`) for all references to the old paths in both `alpine/` and `buildroot/` directories (including Makefiles, package `.mk` files, configs, scripts, workflow files, and `APKBUILD`s) and update them concurrently.
- **Dual-Distro Co-equality**: Both Alpine and Buildroot are co-equal consumers of the shared assets. When modifying or consolidating a shared config/path, ensure the change is implemented in both build targets, verifying that neither target is left broken or using outdated paths.
- **UI Submodules & CI Artifacts**: `minime/ui/allium` and `minime/ui/minui` are git submodules tracking fork branches. UI binaries are compiled by the `build-ui` job matrix inside `build.yml` (musl on ARM64, glibc on AMD64) and passed to `build-os` as ephemeral GitHub Actions run artifacts (`ui-musl`, `ui-glibc`). They are never committed to git and never uploaded to a GitHub Release. At packaging time `genassets.sh` extracts the matching archive from the downloaded artifact into `minime/ui/out/` (ephemeral runner path). Submodule SHAs in `minime` are bumped automatically by `update-submodules.yml` (daily cron + `repository_dispatch`).
- **Minimal UI Codebase Intrusion**: Unless implementing a user-requested feature, restrict UI code modifications strictly to the Minime platform port directory (e.g. `workspace/minime/` in MinUI, `src/platform/minime/` in Allium). Leave shared upstream launcher code untouched. Exceptions are permitted ONLY when:
  - Working around upstream behavior within the platform port directory is excessively complex or hacky (e.g. requiring dozens of lines of workaround vs. a clean one-line fix in shared code).
  - The change objectively fixes crashes, memory corruption, thread deadlocks, or performance regressions across all targets.
- **On-Device Live Verification**: After modifying any code and allowing CI to rebuild artifacts, AI agents must run `just fetch` / `just update` to deploy and empirically verify changes on the live physical hardware target.

## Infrastructure & Scripts

**Mandatory reading for AI agents**: Before making any changes to build or workflow files, read [`docs/minime-workflow.yml`](file:///Users/ilembitov/Projects/minime/docs/minime-workflow.yml) — it is the single source of truth for the full CI pipeline: steps, scripts, dependencies, caches, and outputs.

For detailed documentation of GitHub Actions workflows, build orchestration scripts, entrypoints, and `Justfile` commands, consult [docs/INFRA.md](file:///Users/ilembitov/Projects/minime/docs/INFRA.md).

## Unified Validation Quality Gates

All checks must pass before committing. Do not suppress/bypass warnings.
All gates are defined in the root `Justfile` and must be run via `just`.


- **Fast gates (pre-commit)**: `just validate`
- **CI-only gates**: `just validate-ci`
- **Developer setup**: `just install-hooks`

