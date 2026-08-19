# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

> **Mandatory reading for AI agents**: Read this document before making any changes to build or workflow files. The `.github/workflows/*.yml` files are the executable source of truth for the pipeline; this document is the human-readable reference for it.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `build.yml` — Main Parameter-Driven Build Pipeline
- **Trigger**:
  - `push`: `main` branch filtered to `minime/**`, `src/**`, `.github/workflows/**` (defaults to `alpine / rk3566 / minui`).
  - `workflow_dispatch`: Single target selection via dropdowns (`libc`: `alpine` / `buildroot`, `soc`: `rk3566` / `rk3326` / `h700`, `ui`: `minui` / `muos` / `allium`).
  - `workflow_call`: Reusable entrypoint called by `nightly.yml`.
- **Purpose**: Builds bootloader, cores, UI, and OS image for a single target, uploading `.img.zst` and `.tar.zst` to the `testing` GitHub Release on main.
- **Concurrency**: Per-target `minime-build-${{ github.ref }}-${{ libc }}-${{ soc }}-${{ ui }}` (`cancel-in-progress: true`).
- **Jobs**:
  - `setup` — Computes runner, libc container, ccache/dl paths, and enforces compatibility (`buildroot` + `h700` rejected).
  - `bootloader` — Calls reusable `build-bootloader.yml` (U-Boot for all boards, cached).
  - `cores` — Builds RetroArch cores for the target libc (`cores-{libc}`). Source-fingerprinted binary cache + ccache.
  - `ui` — Builds only the requested UI for the target libc (`ui-{ui}-{libc}`). Source-fingerprinted binary cache + ccache + Cargo target.
  - `build-os` — Runs `make components` (Phase 2) then `make image update` (Phase 4). Caches ccache and distfile DL mirrors; uploads `.img.zst` / `.tar.zst` to `testing` release.

### `nightly.yml` — Daily Regression & Matrix Rebuilds
- **Trigger**: Daily cron at 04:00 UTC (`0 4 * * *`, = 07:00 GMT+3); manual `workflow_dispatch`.
- **Purpose**: Runs a static 15-target matrix over all valid combinations (all except `buildroot + h700`), calling `build.yml` concurrently.

### `build-bootloader.yml` — U-Boot Builder (Reusable)
- **Trigger**: Called by `build.yml`.
- **Purpose**: Builds and caches U-Boot binaries for `rk3326`, `rk3566`, and `h700`. Source-cached by hash of `packages/bootloader/**`.

### `containers.yml` — Build & Push Builder Images
- **Trigger**: Push to `main` on `packages/components/alpine/container/**` or `packages/components/buildroot/container/**`; `workflow_dispatch`.
- **Purpose**: Builds and pushes `ghcr.io/.../minime-musl:latest` (arm64) and `ghcr.io/.../minime-glibc:latest` (amd64) to GHCR. These images are prerequisites for the build pipelines.

### `sync-kernel.yml` — Automated Kernel Version Sync
- **Trigger**: Daily cron at 00:00 UTC. Commits directly to `main`.
- **Purpose**: Runs `packages/image/synckernel.sh` to keep the kernel version pin synced between Alpine's `tinykernel` APKBUILD and Buildroot's kernel config, then drops any patches marked `upstream=master` in `packages/image/kernel-patch-manifest` (their content has landed in mainline).

### `update-submodules.yml` — UI Submodule Bump
- **Trigger**: Daily cron at 02:00 UTC; `repository_dispatch` event `update-submodules`.
- **Purpose**: Runs `git submodule update --remote` on `packages/ui/allium` and `packages/ui/minui`, then commits the bumped SHAs to `main`.

---

## 2. Repository Scripts & Entrypoints

### Build Scripts (`packages/image/`)
- **`packages/bootloader/build.sh`**: Builds U-Boot for `h700`, `rk3326`, or `rk3566` (invoked by the `build-bootloader` reusable workflow in `build-bootloader.yml`). `rk3566` and `rk3326` use the vendor Rockchip boot chain (committed rkbin DDR/BL31 blobs; `rk3326` additionally packs `uboot.img` via `loaderimage` and `trust.img` via `trust_merger`); `h700` builds ATF and U-Boot from source.
- **`packages/cores/buildcores.sh`**: Builds all shared RetroArch cores from `packages/cores/manifest` (single source of truth: recipes, pins, patches) into a flat `out/` dir consumed by both UIs. Invoked by the `build-cores` job.
- **`packages/ui/build.sh`**: Compiles MinUI, Allium, and muOS for a given libc variant (`musl` or `glibc`). Invoked by the `ui` job in `build.yml`. MinUI injects the downloaded cores artifact via `make cores CORES_DIR=...`; Allium copies it into `RetroArch/.retroarch/cores/` and stages its bundled tools (dufs/collie/syncthing) into `.allium/bin/`; muOS applies `packages/ui/muos/patches` to the pristine `frontend` submodule, builds, and stages `bin/` + `muos/internal` `share/`+`script/` + the `packages/ui/muos/overlay` launcher. Outputs archives to `packages/ui/out/` (ephemeral runner path, not committed to git).
- **`packages/image/build.sh`**: Extracts UI binaries from the `ui-{libc}` GH run artifact into the working tree before image assembly.
- **`packages/image/build.sh`**: Central image builder. Consumes compiled target artifacts (`system.erofs`, `Image`, `initramfs`, `*.dtb`, UI binaries) and prebuilt U-Boot binaries; assembles and compresses `{board}-{ui}.img.zst`.
- **`packages/image/build.sh`**: Central OTA package generator. Packages the same artifacts into `{board}-{ui}.tar.zst` for live updates.
- **`packages/image/synckernel.sh`**: Bumps the kernel version pin and `sha512sums` in Alpine's APKBUILD and Buildroot's config to the latest Alpine-stable release.
- **`packages/image/gentraits.sh`**: Device registry generator + validator. Emits overlay DTS for derived devices into the kernel tree at build time, prints the shipped-DTB list, and cross-references the registry against the Buildroot DTS config (`check`). The registry is the single source of truth for devices.
- **`packages/image/preparelinux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.

### Validation & Helper Scripts (`scripts/`)
Validation is **local-only and owned by this folder** — every check lives in a
`scripts/check-*.sh` invoked via `just`; there is no CI validation job.
- **`scripts/check-traits.sh`**: Validates device hardware traits configuration. Structural/schema and DTB cross-reference checks are delegated to `traits-gen check`; keeps the input keycode/axis semantic checks.
- **`scripts/check-kernel-config.sh`**: Validates kernel config fragments across all boards for duplicates, symbol syntax, and vendor enabler toggles.
- **`scripts/check-firmware.sh`**: Verifies all required firmware files (`CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` entries) exist in firmware directories.
- **`scripts/check-patches.sh`**: Ensures all `.patch` files on disk are referenced in build manifests (`APKBUILD`, Makefile, `series`).
- ****: Lints SHA-256 (64 hex) / SHA-512 (128 hex) hash string formats in Buildroot `.hash` files and `APKBUILD`s.
- **`scripts/check-package-lists.sh`**: Cross-checks local package lists so every referenced package is built.
- **`scripts/check-scripts.sh` / `check-apkbuilds.sh` / `check-openrc.sh`**: shellcheck over `*.sh`, `APKBUILD`, and OpenRC `init.d` scripts.
- **`scripts/check-git.sh`**: `git diff --check` (whitespace + conflict markers) on staged and working-tree diffs.
- **`scripts/check-workflows.sh`**: actionlint over `.github/workflows/*.yml`.
- **`scripts/check-build-flow.sh`**: Enforces the packaging/compilation split of `build.sh` / `mkimage.sh` / `mkupdate.sh` / `genassets.sh`.
- **`scripts/install-hooks.sh`**: Installs `pre-commit`/`pre-push` hooks that run `just validate-static` (pre-push forwards to `git lfs pre-push`).
- ****: Generic push-and-apply OTA helper (stop UI → FTP upload → apply → reboot) for locally built update packages, e.g. the boot-profiler's instrumented initramfs packages. Normal OTA updates run **on-device** via `/usr/bin/update.sh`.
- **`scripts/fetch-asset.sh`**: Downloads a named release asset (`.img.zst` or `.tar.zst`) from the latest `testing` GitHub Release.
- **`scripts/remote-cmd.sh`**: Executes arbitrary shell commands on target device over telnet using `target_ip` from `deploy.cfg`.
- **`scripts/remote-upload.sh`**: Uploads a local file to the target device over FTP.

---

## 3. Developer Command Utilities (`Justfile`)

All local developer commands are managed via `Justfile` and executed with `just`:

| Recipe | What it checks | Shell / Tool | Notes |
|---|---|---|---|
| `just validate` | **Full local gate** | `just` | Fast static checks + UI formatting (`check-allium`/`check-minui`/`check-yabause`; needs Rust + clang). |
| `just validate-static` | **Fast static gate** | `just` | No cargo/clang toolchains. Run by the `pre-commit`/`pre-push` hooks. |
| `just validate-ci` | **Buildroot-dependent gate** | `just` | Runs `validate` plus `check-defconfigs` and `check-packages` (requires upstream Buildroot tree). |
| `check-scripts` | `*.sh` files (all distros) | auto from shebang | Syntax (`sh -n`), shellcheck, exec bit. Excludes upstream Buildroot. |
| `check-apkbuilds` | `alpine/aports/**/APKBUILD` | `--shell=sh` | Syntax and shellcheck targeting ash; no shebang/exec check. |
| `check-openrc` | `packages/components/boards/*/overlay/etc/init.d/*` | `--shell=sh` | Shellcheck targeting ash; enforces executable bit. |
| `check-traits` | Device traits configuration | `scripts/check-traits.sh` | Delegates registry validation to `traits-gen check`; adds input/axis checks. |
| `check-kernel-config` | Merged kernel config fragments | `scripts/check-kernel-config.sh` | Detects duplicate symbols, syntax errors, and orphaned vendor toggles. |
| `check-firmware` | Required firmware files | `scripts/check-firmware.sh` | Verifies `CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` files exist on disk. |
| `check-patches` | `.patch` files across repository | `scripts/check-patches.sh` | Ensures all `.patch` files are referenced in build manifests. |
| `check-hashes` | Package manifests `.hash` / `APKBUILD` |  | Validates SHA-256 (64 hex) & SHA-512 (128 hex) string formats. |
| `check-package-lists` | Local package lists | `scripts/check-package-lists.sh` | Cross-checks Alpine/Buildroot lists so every referenced package is built. |
| `check-git` | Staged + working-tree diff | `scripts/check-git.sh` | `git diff --check` (whitespace + conflict markers). |
| `check-workflows` | `.github/workflows/*.yml` | `scripts/check-workflows.sh` | actionlint via mise. |
| `check-build-flow` | Packaging/compilation split | `scripts/check-build-flow.sh` | Enforces `build.sh` (compilation-only) vs `mkimage.sh`/`mkupdate.sh`/`genassets.sh` (packaging-only). |
| `just deploy <os> <board> <ui> [disk]` | Flash latest testing image | `fetch-asset.sh` + `dd` / `diskutil` | Fetches the latest `minime-<os>-<board>-<ui>.img.zst`, writes it to target disk, injects `wifi.cfg`, ejects card. Also accepts an explicit image path. Supports `deploy.cfg` + `minime` label guard. |
| `just shell <cmd> [ip]` | Run a remote shell command | `scripts/remote-cmd.sh` | Runs a command on the target over SSH by default (dropbear, blank-password root, enabled by default); `--telnet` forces telnet. The command is passed via a temp file so quotes/pipes survive. Uses `target_ip` in `deploy.cfg`. The OTA update path is the **on-device** `/usr/bin/update.sh [target] [ui]` (e.g. `just shell "update.sh minui"`, `just shell "update.sh buildroot"`). |
| `just upload <file> [remote_path] [ip]` | Copy a file to the device | `scripts/scp-upload.sh` / `scripts/remote-upload.sh` | Copies a local file to the target over SSH/scp by default (any path as root; `ssh 'cat >'`, dropbear ships no scp); `--ftp` uses FTP, limited to the `/mnt/sdcard` root. |
| `just build-allium [target=musl]` | Build Allium locally | `cargo build` | Builds Allium binaries for `musl` (default) or `glibc`. |
| `just build-minui [target=musl]` | Build MinUI locally | `make system cores package` | Builds the MinUI binaries/cores for the `minime` platform. |
| `just install-hooks` | Git pre-commit/pre-push hooks | `scripts/install-hooks.sh` | Installs hooks that run `just validate-static` (pre-push also forwards to `git lfs pre-push`). |

> `just fetch`, `just fetch-update`, `just update`, and `just check-version` are removed. OTA updates run **on-device** via `/usr/bin/update.sh [target] [ui]` (see the `live-test` skill). `just deploy` fetches the latest testing image on demand via `scripts/fetch-asset.sh`.
