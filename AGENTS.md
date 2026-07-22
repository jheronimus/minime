# Minime (Custom Linux/Buildroot firmware)

Consolidated monorepo for Minime firmware. Minimal Buildroot firmware for Anbernic handhelds (RK3326/H700/RK3566; tested on RG35xxSP v1) with mainline kernel, libmali, auto-connecting Wi-Fi (`wpa_supplicant`), and passwordless telnet/ftp (`busybox`).

## Monorepo Structure

- `alpine/`: Core Alpine build system.
  - `aports/`: Custom Alpine package ports.
  - `board/`: Alpine board configurations and scripts.
  - `bootloader/`: Prebuilt bootloader blobs (canonical location). Built by the [Prebuild Bootloaders workflow](file:///Users/ilembitov/Projects/minime/.github/workflows/bootloader.yml) (manual dispatch). `h700/` has `u-boot-sunxi-with-spl.bin`; `rk3326/`/`rk3566/` have `idbloader.img` + `u-boot.itb`; `rk3566/rkbin/` also has the committed `bl31.elf` (Rockchip proprietary, hybrid mainline U-Boot + rkbin ATF).
  - `configs/`: Alpine build configuration flags.
- `buildroot/`: Core Buildroot build system (formerly `minime/`).
  - `Makefile`: Docker/Colima setups, builds, configs.
  - `external/`: Custom Buildroot (`BR2_EXTERNAL`).
    - `configs/`: Defconfigs and config fragments.
      - `minime_common.config`: Shared Buildroot options (arch, toolchain, packages, rootfs).
      - `bootloader/`: U-Boot/ATF re-enabling fragments, used ONLY by the [Prebuild Bootloaders workflow](file:///Users/ilembitov/Projects/minime/.github/workflows/bootloader.yml). Firmware defconfigs do NOT build U-Boot.
    - `board/h700/`: H700 overlays, DTS, patches, config fragments (`linux.config`/`uboot.config`), scripts.
    - `package/`: Custom packages (Mali, UI, ROMs) pulled at build time.
  - `buildroot/`: Upstream Buildroot (tarball download at build time).
  - `out/<board>/` / `logs/`: Bootable images / build logs.
- `docs/`: Specs and documentation (adr/ for ADRs, spec/ for specifications).
- `src/`: Shared source code (libmali GPU userspace, mali-kbase kernel driver, bootsplash).
  - `mali-kbase/`: ARM Mali Bifrost kernel driver source (out-of-tree module).
  - `libmali/`: ARM Mali userspace driver source + proprietary blobs (blobs/, hook/, shim/, scripts/, include/).
- `roms/`: Preloaded ROMs package.

## File Locations & Repository Mapping

A short summary of where important files live. For precise paths, consult [docs/MAP.md](file:///Users/ilembitov/Projects/minime/docs/MAP.md).

- **Shared Assets (Alpine-owned)**: All shared configuration files, DTS/DTB files, kernel patches, firmware blobs, and hardware traits live in the `alpine/board/` folder. Buildroot's makefiles and build scripts reference or import them directly from there.
  - `alpine/board/common/scripts/` is the canonical home for cross-distro runtime scripts (`wifi.sh`, `ui.sh`, `traits.sh`). Alpine's APKBUILD installs them via `install`; Buildroot's `post-build.sh` copies them into `$TARGET_DIR/usr/share/minime/scripts/`. **Never maintain separate copies in each distro's subtree.**
- **Unshareable Distro-Specific Files**: Files that cannot be shared (such as OpenRC vs. BusyBox init scripts and platform-specific packaging recipes/scaffolding) live in their respective distro subdirectories and must be kept in sync manually.
- **Shared Source Code (`src/`)**: Holds local, self-contained source code vaults for modules built in both environments (e.g. `bootsplash`, `libmali`, and `mali-kbase`).

## Local Alpine Builds (Containerized)

Alpine builds require a Linux/musl environment with APK packaging tools, and must be compiled using Podman or Docker (with `--platform linux/arm64` cross-compilation support).

Commands are run within the `alpine/` subdirectory:
- **Build Container**: `make prepare` compiles the `minime-builder-alpine` docker image.
- **Build Image**: `make image BOARD=<board>` (e.g. `BOARD=rk3566`) compiles the final bootable firmware image.
- **Interactive Shell**: `make shell` logs into the build environment for manual debugging/packaging.

## Agent Directives (Buildroot Quirks)

- **Architecture & Optimization Knowledge**: Store all architectural decisions, filesystem/kernel performance optimizations, and design rationale in Architecture Decision Records under `docs/adr/` (e.g. `docs/adr/0001-fat32-cluster-and-image-sizing.md`).
- **No Temporary Workarounds**: Fix local/runner states directly in the environment. Never add temporary configs, scripts, or hooks to build logic.
- **Path and Restructuring Integrity**: When moving, renaming, or consolidating files or directories (e.g., board assets, source paths, packages), you MUST perform a repository-wide search (`grep`) for all references to the old paths in both `alpine/` and `buildroot/` directories (including Makefiles, package `.mk` files, configs, scripts, workflow files, and `APKBUILD`s) and update them concurrently.
- **Dual-Distro Co-equality**: Both Alpine and Buildroot are co-equal consumers of the shared assets. When modifying or consolidating a shared config/path, ensure the change is implemented in both build targets, verifying that neither target is left broken or using outdated paths.

## Commit Requirements for Remote Builds

Push changes to the respective branch on `jheronimus/minime` to trigger CI builds.

## Scripts & Git Exclusions

`scripts/` is strictly for Makefile/pipeline orchestration (`prepare-linux.sh`, `build-bootloader.sh`, `update_kernel_version.py`) and developer utilities.

## CI Pipeline & Remote Runner

Builds compile on GitHub Actions runner. Workflows for `buildroot/` and `alpine/` are located under `.github/workflows/`.

## Unified Validation Quality Gates

All checks must pass before committing. Do not suppress/bypass warnings.
All gates are defined in the root `Justfile` and must be run via `just`.

### Fast gates — run before every commit

```sh
just validate
```

Runs: `check-scripts`, `check-apkbuilds`, `check-openrc`, `check-traits`, `check-git`.

| Recipe | What it checks | Shell flag | Notes |
|---|---|---|---|
| `check-scripts` | `*.sh` files (all distros) | auto from shebang | Enforces exec bit |
| `check-apkbuilds` | `alpine/aports/**/APKBUILD` | `--shell=sh` | ash target; no shebang/exec check |
| `check-openrc` | `alpine/aports/**/files/etc/init.d/*` | `--shell=sh` | ash target; enforces exec bit |
| `check-traits` | `alpine/board/common/check-traits.sh` | — | Traits config validation |
| `check-git` | staged diff | — | Whitespace / merge markers |

### CI-only gates — require upstream Buildroot tree

```sh
just validate-ci
```

Runs `validate` plus `check-defconfigs` and `check-packages`.

- **`check-defconfigs`**: merges and validates our config fragments for all boards via `make defconfig BOARD=<board>`.
- **`check-packages`**: lints our `buildroot/external/package/` files via `python3 buildroot/buildroot/utils/check-package`.
- **Proactive Package Cleaning**: Run `make buildroot-<pkg>-dirclean BOARD=<board>` locally when a package is modified.

### Shell conventions enforced by shellcheck

- All scripts target **POSIX sh / busybox ash** unless they carry a `#!/bin/bash` shebang.
- APKBUILDs: no shebang (sourced by `abuild`), targeting ash. `SC2154` suppressed per-file (abuild injects `srcdir`/`builddir`/`pkgdir`).
- OpenRC init.d scripts: `#!/sbin/openrc-run`, targeting ash. `SC2034` suppressed per-file (openrc-run framework globals).
- OpenRC service names are **unprefixed** (`wifi`, `modules`, `bluetooth`, etc.). Do not add a `minime-` prefix.

### Developer setup

Install the pre-commit hook to enforce `just validate` on every commit:

```sh
just install-hooks
```
