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
  - `genimage/`: Centralized image assembly (`build-image.sh`) and update package generation (`build-update.sh`).
- `docs/`: Specs and documentation (adr/ for ADRs, spec/ for specifications).
- `src/`: Shared source code (libmali GPU userspace, mali-kbase kernel driver).
  - `mali-kbase/`: ARM Mali Bifrost kernel driver source (out-of-tree module).
  - `libmali/`: ARM Mali userspace driver source + proprietary blobs.
- `roms/`: Preloaded ROMs package.

## File Locations & Repository Mapping

Minime supports two build targets: Alpine and Buildroot, housed under `minime/targets/`. All shared configuration files, DTS/DTB files, kernel patches, firmware blobs, and hardware traits live in the central `minime/boards/` directory. Target build scripts reference or import them directly from there.

For precise paths, consult [docs/MAP.md](file:///Users/ilembitov/Projects/minime/docs/MAP.md).

For init scripts, `minime/boards/common/overlay/etc/init.d/` is the single source of truth for cross-distro OpenRC services. At build time, target builders copy these init scripts into their rootfs before building `system.erofs`.

- **Shared Source Code (`src/`)**: Holds local, self-contained source code vaults for modules built in both environments (e.g. `libmali` and `mali-kbase`).

## Local Target Builds

Alpine and Buildroot targets are built from their respective directories in `minime/targets/`:
- **Alpine**: `make -C minime/targets/alpine image BOARD=<board>`
- **Buildroot**: `make -C minime/targets/buildroot image BOARD=<board>`

## Agent Directives (Buildroot Quirks)

- **No Manual Workflow Dispatch**: Every push to `main` automatically triggers the Alpine and Buildroot build workflows. **Never** use `gh workflow run` to manually dispatch build workflows — this causes race conditions where concurrent builds corrupt the `testing` release assets. Only use manual dispatch for the bootloader workflow (`bootloader.yml`), which requires explicit invocation.
- **Cancel Stale Jobs**: If you have made several pushes in succession, run `gh run list` and cancel any in-progress or queued builds from earlier pushes — only the latest commit matters. Never allow more than one job of any given kind (Alpine, Buildroot, Bootloader) to run concurrently.
- **Architecture & Optimization Knowledge**: Store all architectural decisions, filesystem/kernel performance optimizations, and design rationale in Architecture Decision Records under `docs/adr/` (e.g. `docs/adr/0001-fat32-cluster-and-image-sizing.md`).
- **No Temporary Workarounds**: Fix local/runner states directly in the environment. Never add temporary configs, scripts, or hooks to build logic.
- **Path and Restructuring Integrity**: When moving, renaming, or consolidating files or directories (e.g., board assets, source paths, packages), you MUST perform a repository-wide search (`grep`) for all references to the old paths in both `alpine/` and `buildroot/` directories (including Makefiles, package `.mk` files, configs, scripts, workflow files, and `APKBUILD`s) and update them concurrently.
- **Dual-Distro Co-equality**: Both Alpine and Buildroot are co-equal consumers of the shared assets. When modifying or consolidating a shared config/path, ensure the change is implemented in both build targets, verifying that neither target is left broken or using outdated paths.
- **Shared Scripts Distro Pattern**: Files that can be shared between Alpine and Buildroot with minimal distro-specific differences must isolate all `DISTRO`-dependent logic in a single `case "${DISTRO}" in ... esac` block at the very top of the script (immediately after arg parsing/validation). The rest of the script must be distro-agnostic, using only variables set by that block (e.g. `DISTRO_SUFFIX`, resolved paths). Reference implementation: `alpine/board/common/post-image.sh`.

## Infrastructure & Scripts

For detailed documentation of GitHub Actions (GA) workflows, build orchestration scripts, entrypoints, and `Justfile` commands, consult [docs/INFRA.md](file:///Users/ilembitov/Projects/minime/docs/INFRA.md).

## Unified Validation Quality Gates

All checks must pass before committing. Do not suppress/bypass warnings.
All gates are defined in the root `Justfile` and must be run via `just`.
For detailed descriptions of quality gate recipes and shell conventions, see [docs/INFRA.md](file:///Users/ilembitov/Projects/minime/docs/INFRA.md).

- **Fast gates (pre-commit)**: `just validate`
- **CI-only gates**: `just validate-ci`
- **Developer setup**: `just install-hooks`

