# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

> **Mandatory reading for AI agents**: Read this document before making any changes to build or workflow files. The `.github/workflows/*.yml` files are the executable source of truth for the pipeline; this document is the human-readable reference for it.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `build-musl.yml` / `build-glibc.yml` — Main Build Pipelines
- **Trigger**: `build-musl.yml` (alpine): push to `main` filtered to `minime/**` and `src/**` (shared source: remote/benchmark/display/libmali/kernel); daily cron at 04:00 UTC (`0 4 * * *`, = 07:00 GMT+3); `workflow_dispatch` (comma-separated `targets` input of alpine boards, default `all`). `build-glibc.yml` (buildroot): same daily cron and `workflow_dispatch` (buildroot boards); **no push trigger**.
- **Purpose**: Builds bootloaders, UIs, OS images, and OTA update packages. Push to `main` builds only the fast-path alpine board (`FAST_PATH_TARGET` env at the top of `build-musl.yml`, default `rk3566`); the daily cron and `all` dispatch rebuild every board of that distro. Uploads `.img.zst` / `.tar.zst` to the `testing` GitHub Release on any main-branch run.
- **Concurrency**: Each workflow has its own `concurrency` group (`cancel-in-progress: true`) keyed on `github.ref` — the newest run wins within a workflow, and musl/glibc runs may overlap because they upload disjoint assets to `testing`. A cancelled run is expected behaviour (a newer commit/dispatch superseded it), not an error.
- **Jobs** (identical in both, differing only in libc values / alpine-vs-buildroot target dir):
  - `setup` — computes the board matrix: `push` → `[FAST_PATH_TARGET]`, cron → all boards of the distro, `workflow_dispatch` → parsed `targets` input (fails on unknown boards).
  - `bootloader` — calls the shared reusable workflow `build-bootloader.yml` (U-Boot for all three boards `{rk3326, rk3566, h700}`, cached by hash of `minime/uboot/**`). `rk3326`/`rk3566` use the vendor rkbin boot chain, `h700` builds ATF from source.
  - `build-cores-{libc}` — builds the shared RetroArch cores from `minime/build/cores/manifest` via `buildcores.sh`. Uploads the flat `cores-{libc}` artifact consumed by the UI job. Cached by a **source-only** key (`manifest` + `buildcores.sh` + `patches/**`) so unchanged cores reuse artifacts (~1 min vs 4–6 min).
  - `build-ui-{libc}` — compiles MinUI and Allium (musl on ARM64 inside `minime-musl:latest`; glibc on AMD64 cross inside `minime-glibc:latest`). Cached by submodule HEADs (allium, its nested RetroArch-patch/RetroArch, minui) + `minime/build/mkui.sh`; Allium cargo `target/` dirs (workspace + dufs/collie) cached separately keyed on their `Cargo.lock`.
  - `build-os` (matrix over the `setup` board list) — runs `make components` then `make image update` (once per UI). Uses `minime/targets/{alpine,buildroot}`, per-distro ccache, a board-shared DL dir, the matching `ui-{libc}` artifact, and the matching upload path. The Alpine kernel tarball is pre-downloaded into the DL cache with a retrying curl + sha512 verification so a transient CDN truncation self-heals instead of aborting the build.
- **Caches**: `bootloader-*`, `cores-{libc}-*`, `ccache-cores-{libc}-*`, `ui-{libc}-*`, `ccache-ui-{libc}-*`, `allium-target-{libc}-*`, `ccache-{os}-{board}-*`, `dl-{os}-*` (alpine distfiles are shared across boards; buildroot keys per board). Binary caches are keyed on source fingerprints (never on build outputs); ccache is layered on top so a cache miss only recompiles changed objects. Every Save step runs when its build step ran (not on a file-missing check), so rebuilds always re-seed the cache.
- **Rule**: Push-to-main only drives `build-musl.yml`; `workflow_dispatch` is for targeted on-demand builds of either distro. The per-workflow concurrency group enforces one active build per workflow/branch — never manually cancel or re-dispatch a cancelled run.

### `containers.yml` — Build & Push Builder Images
- **Trigger**: Push to `main` on `minime/targets/alpine/container/**` or `minime/targets/buildroot/container/**`; `workflow_dispatch`.
- **Purpose**: Builds and pushes `ghcr.io/.../minime-musl:latest` (arm64) and `ghcr.io/.../minime-glibc:latest` (amd64) to GHCR. These images are prerequisites for the build pipelines.

### `sync-kernel.yml` — Automated Kernel Version Sync
- **Trigger**: Daily cron at 00:00 UTC. Commits directly to `main`.
- **Purpose**: Runs `minime/build/synckernel.sh` to keep the kernel version pin synced between Alpine's `tinykernel` APKBUILD and Buildroot's kernel config.

### `update-submodules.yml` — UI Submodule Bump
- **Trigger**: Daily cron at 02:00 UTC; `repository_dispatch` event `update-submodules`.
- **Purpose**: Runs `git submodule update --remote` on `minime/ui/allium` and `minime/ui/minui`, then commits the bumped SHAs to `main`.

---

## 2. Repository Scripts & Entrypoints

### Build Scripts (`minime/build/`)
- **`minime/build/mkbootloader.sh`**: Builds U-Boot for `h700`, `rk3326`, or `rk3566` (invoked by the `build-bootloader` reusable workflow in `build-bootloader.yml`). `rk3566` and `rk3326` use the vendor Rockchip boot chain (committed rkbin DDR/BL31 blobs; `rk3326` additionally packs `uboot.img` via `loaderimage` and `trust.img` via `trust_merger`); `h700` builds ATF and U-Boot from source.
- **`minime/build/cores/buildcores.sh`**: Builds all shared RetroArch cores from `minime/build/cores/manifest` (single source of truth: recipes, pins, patches) into a flat `out/` dir consumed by both UIs. Invoked by the `build-cores` job.
- **`minime/build/mkui.sh`**: Compiles MinUI and Allium for a given libc variant (`musl` or `glibc`). Invoked by the `build-ui-musl` / `build-ui-glibc` jobs in `build-musl.yml` / `build-glibc.yml`. MinUI injects the downloaded cores artifact via `make cores CORES_DIR=...`; Allium copies it into `RetroArch/.retroarch/cores/` and stages its bundled tools (dufs/collie/syncthing) into `.allium/bin/`. Outputs archives to `minime/ui/out/` (ephemeral runner path, not committed to git).
- **`minime/build/genassets.sh`**: Extracts UI binaries from the `ui-{libc}` GH run artifact into the working tree before image assembly.
- **`minime/build/mkimage.sh`**: Central image builder. Consumes compiled target artifacts (`system.erofs`, `Image`, `initramfs`, `*.dtb`, UI binaries) and prebuilt U-Boot binaries; assembles and compresses `{board}-{ui}.img.zst`.
- **`minime/build/mkupdate.sh`**: Central OTA package generator. Packages the same artifacts into `{board}-{ui}.tar.zst` for live updates.
- **`minime/build/synckernel.sh`**: Bumps the kernel version pin and `sha512sums` in Alpine's APKBUILD and Buildroot's config to the latest Alpine-stable release.
- **`minime/build/preparelinux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.

### Validation & Helper Scripts (`scripts/`)
Validation is **local-only and owned by this folder** — every check lives in a
`scripts/check-*.sh` invoked via `just`; there is no CI validation job.
- **`scripts/check-traits.sh`**: Validates device hardware traits configuration against the trait schema for all boards.
- **`scripts/check-kernel-config.sh`**: Validates kernel config fragments across all boards for duplicates, symbol syntax, and vendor enabler toggles.
- **`scripts/check-firmware.sh`**: Verifies all required firmware files (`CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` entries) exist in firmware directories.
- **`scripts/check-patches.sh`**: Ensures all `.patch` files on disk are referenced in build manifests (`APKBUILD`, Makefile, `series`).
- **`scripts/check-hashes.sh`**: Lints SHA-256 (64 hex) / SHA-512 (128 hex) hash string formats in Buildroot `.hash` files and `APKBUILD`s.
- **`scripts/check-package-lists.sh`**: Cross-checks local package lists so every referenced package is built.
- **`scripts/check-scripts.sh` / `check-apkbuilds.sh` / `check-openrc.sh`**: shellcheck over `*.sh`, `APKBUILD`, and OpenRC `init.d` scripts.
- **`scripts/check-git.sh`**: `git diff --check` (whitespace + conflict markers) on staged and working-tree diffs.
- **`scripts/check-workflows.sh`**: actionlint over `.github/workflows/*.yml`.
- **`scripts/check-build-flow.sh`**: Enforces the packaging/compilation split of `build.sh` / `mkimage.sh` / `mkupdate.sh` / `genassets.sh`.
- **`scripts/install-hooks.sh`**: Installs `pre-commit`/`pre-push` hooks that run `just validate-static` (pre-push forwards to `git lfs pre-push`).
- **`scripts/update-device.sh`**: Generic push-and-apply OTA helper (stop UI → FTP upload → apply → reboot) for locally built update packages, e.g. the boot-profiler's instrumented initramfs packages. Normal OTA updates run **on-device** via `/usr/bin/update.sh`.
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
| `check-openrc` | `minime/boards/*/overlay/etc/init.d/*` | `--shell=sh` | Shellcheck targeting ash; enforces executable bit. |
| `check-traits` | Device traits configuration | `scripts/check-traits.sh` | Validates board hardware traits config against schema. |
| `check-kernel-config` | Merged kernel config fragments | `scripts/check-kernel-config.sh` | Detects duplicate symbols, syntax errors, and orphaned vendor toggles. |
| `check-firmware` | Required firmware files | `scripts/check-firmware.sh` | Verifies `CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` files exist on disk. |
| `check-patches` | `.patch` files across repository | `scripts/check-patches.sh` | Ensures all `.patch` files are referenced in build manifests. |
| `check-hashes` | Package manifests `.hash` / `APKBUILD` | `scripts/check-hashes.sh` | Validates SHA-256 (64 hex) & SHA-512 (128 hex) string formats. |
| `check-package-lists` | Local package lists | `scripts/check-package-lists.sh` | Cross-checks Alpine/Buildroot lists so every referenced package is built. |
| `check-git` | Staged + working-tree diff | `scripts/check-git.sh` | `git diff --check` (whitespace + conflict markers). |
| `check-workflows` | `.github/workflows/*.yml` | `scripts/check-workflows.sh` | actionlint via mise. |
| `check-build-flow` | Packaging/compilation split | `scripts/check-build-flow.sh` | Enforces `build.sh` (compilation-only) vs `mkimage.sh`/`mkupdate.sh`/`genassets.sh` (packaging-only). |
| `just deploy <os> <board> <ui> [disk]` | Flash latest testing image | `fetch-asset.sh` + `dd` / `diskutil` | Fetches the latest `minime-<os>-<board>-<ui>.img.zst`, writes it to target disk, injects `wifi.cfg`, ejects card. Also accepts an explicit image path. Supports `deploy.cfg` + `minime` label guard. |
| `just shell <cmd> [ip]` | Run a remote shell command | `scripts/remote-cmd.sh` | Runs a command on the target over SSH by default (dropbear, blank-password root, enabled by default); `--telnet` forces telnet. The command is passed via a temp file so quotes/pipes survive. Uses `target_ip` in `deploy.cfg`. The OTA update path is the **on-device** `/usr/bin/update.sh <minui|allium>` (e.g. `just shell "update.sh minui"`). |
| `just upload <file> [remote_path] [ip]` | Copy a file to the device | `scripts/scp-upload.sh` / `scripts/remote-upload.sh` | Copies a local file to the target over SSH/scp by default (any path as root; `ssh 'cat >'`, dropbear ships no scp); `--ftp` uses FTP, limited to the `/mnt/sdcard` root. |
| `just build-allium [target=musl]` | Build Allium locally | `cargo build` | Builds Allium binaries for `musl` (default) or `glibc`. |
| `just build-minui [target=musl]` | Build MinUI locally | `make system cores package` | Builds the MinUI binaries/cores for the `minime` platform. |
| `just install-hooks` | Git pre-commit/pre-push hooks | `scripts/install-hooks.sh` | Installs hooks that run `just validate-static` (pre-push also forwards to `git lfs pre-push`). |

> `just fetch`, `just fetch-update`, `just update`, and `just check-version` are removed. OTA updates run **on-device** via `/usr/bin/update.sh <minui|allium>` (see the `live-test` skill). `just deploy` fetches the latest testing image on demand via `scripts/fetch-asset.sh`.
