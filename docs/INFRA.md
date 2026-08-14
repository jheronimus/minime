# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

> **Mandatory reading for AI agents**: Read this document before making any changes to build or workflow files. The `.github/workflows/*.yml` files are the executable source of truth for the pipeline; this document is the human-readable reference for it.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `build.yml` — Main Build Pipeline
- **Trigger**: Push to `main` filtered to `minime/**`; daily cron at 04:00 UTC (`0 4 * * *`, = 07:00 GMT+3); `workflow_dispatch` with a comma-separated `targets` input (default `all`).
- **Purpose**: Builds bootloaders, UIs, OS images, and OTA update packages. Push to `main` builds only the fast-path target (`FAST_PATH_TARGET` env at the top of `build.yml`, default `alpine/rk3566`); the daily cron and `all` dispatch build every supported combo (`alpine/{h700,rk3326,rk3566}`, `buildroot/{rk3326,rk3566}`). Uploads `.img.zst` / `.tar.zst` to the `testing` GitHub Release on any main-branch run.
- **Concurrency**: A `concurrency` group (`cancel-in-progress: true`) keyed on `github.ref` allows only one build per branch at a time — the newest run cancels stale ones. A cancelled run is expected behaviour (a newer commit/dispatch superseded it), not an error.
- **Jobs**:
  - `setup` — computes the target matrix from the trigger: `push` → `[FAST_PATH_TARGET]`, `schedule` → all 5 combos, `workflow_dispatch` → parsed `targets` input (fails on unknown targets). Emits `targets` and `os_list` consumed by every downstream job.
  - `build-bootloader` — builds U-Boot for all three boards (`rk3326`, `rk3566`, `h700`) inside `minime-glibc:latest` on AMD64; `rk3326`/`rk3566` use the vendor rkbin boot chain, `h700` builds ATF from source. Cached by hash of `minime/uboot/**`.
  - `build-cores` (matrix: `musl` / `glibc`) — builds the shared RetroArch cores from `minime/build/cores/manifest` via `buildcores.sh`, once for both UIs. Each cell is gated on whether its libc's OS is in the target set (musl→alpine, glibc→buildroot). Uploads the flat `cores-{libc}` artifact consumed by the UI jobs. Cached by a **source-only** key (`manifest` + `buildcores.sh` + `patches/**`) so unchanged cores reuse artifacts (~1 min vs 4–6 min).
  - `build-ui-musl` / `build-ui-glibc` — compile MinUI and Allium per libc **in parallel**, each gated on its OS being in the target set. musl on ARM64 inside `minime-musl:latest`; glibc on AMD64 (cross). Cached by submodule HEADs (allium, its nested RetroArch-patch/RetroArch, minui) + `minime/build/mkui.sh`; Allium cargo `target/` dirs (workspace + dufs/collie) cached separately keyed on their `Cargo.lock`.
  - `build-os` (matrix from `setup.targets`) — runs `make components` then `make image update` (once per UI). `matrix.os` selects the target dir, ccache/DL cache dirs, UI artifact (`ui-{libc}`), and upload path. Needs bootloader + both UI jobs and runs even when a UI job was skipped (`!cancelled() && !failure()`).
- **Caches**: `bootloader-*`, `cores-{libc}-*`, `ccache-cores-{libc}-*`, `ui-{libc}-*`, `ccache-ui-{libc}-*`, `allium-target-{libc}-*`, `ccache-{os}-{board}-*`, `dl-{os}-{board}-*`. Binary caches are keyed on source fingerprints (never on build outputs); ccache is layered on top so a cache miss only recompiles changed objects. Every Save step runs when its build step ran (not on a file-missing check), so rebuilds always re-seed the cache.
- **Rule**: Push-to-main is the only automatic trigger; `workflow_dispatch` is for targeted on-demand builds. The concurrency group enforces one active build per branch — never manually cancel or re-dispatch a cancelled run.

### `containers.yml` — Build & Push Builder Images
- **Trigger**: Push to `main` on `minime/targets/alpine/container/**` or `minime/targets/buildroot/container/**`; `workflow_dispatch`.
- **Purpose**: Builds and pushes `ghcr.io/.../minime-musl:latest` (arm64) and `ghcr.io/.../minime-glibc:latest` (amd64) to GHCR. These images are prerequisites for `build.yml`.

### `sync-kernel.yml` — Automated Kernel Version Sync
- **Trigger**: Daily cron at 00:00 UTC. Commits directly to `main`.
- **Purpose**: Runs `minime/build/synckernel.sh` to keep the kernel version pin synced between Alpine's `tinykernel` APKBUILD and Buildroot's kernel config.

### `update-submodules.yml` — UI Submodule Bump
- **Trigger**: Daily cron at 02:00 UTC; `repository_dispatch` event `update-submodules`.
- **Purpose**: Runs `git submodule update --remote` on `minime/ui/allium` and `minime/ui/minui`, then commits the bumped SHAs to `main`.

---

## 2. Repository Scripts & Entrypoints

### Build Scripts (`minime/build/`)
- **`minime/build/mkbootloader.sh`**: Builds U-Boot for `h700`, `rk3326`, or `rk3566` (invoked by the `build-bootloader` job in `build.yml`). `rk3566` and `rk3326` use the vendor Rockchip boot chain (committed rkbin DDR/BL31 blobs; `rk3326` additionally packs `uboot.img` via `loaderimage` and `trust.img` via `trust_merger`); `h700` builds ATF and U-Boot from source.
- **`minime/build/cores/buildcores.sh`**: Builds all shared RetroArch cores from `minime/build/cores/manifest` (single source of truth: recipes, pins, patches) into a flat `out/` dir consumed by both UIs. Invoked by the `build-cores` job.
- **`minime/build/mkui.sh`**: Compiles MinUI and Allium for a given libc variant (`musl` or `glibc`). Invoked by the `build-ui-musl` / `build-ui-glibc` jobs in `build.yml`. MinUI injects the downloaded cores artifact via `make cores CORES_DIR=...`; Allium copies it into `RetroArch/.retroarch/cores/` and stages its bundled tools (dufs/collie/syncthing) into `.allium/bin/`. Outputs archives to `minime/ui/out/` (ephemeral runner path, not committed to git).
- **`minime/build/genassets.sh`**: Extracts UI binaries from the `ui-{libc}` GH run artifact into the working tree before image assembly.
- **`minime/build/mkimage.sh`**: Central image builder. Consumes compiled target artifacts (`system.erofs`, `Image`, `initramfs`, `*.dtb`, UI binaries) and prebuilt U-Boot binaries; assembles and compresses `{board}-{ui}.img.zst`.
- **`minime/build/mkupdate.sh`**: Central OTA package generator. Packages the same artifacts into `{board}-{ui}.tar.zst` for live updates.
- **`minime/build/synckernel.sh`**: Bumps the kernel version pin and `sha512sums` in Alpine's APKBUILD and Buildroot's config to the latest Alpine-stable release.
- **`minime/build/preparelinux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.

### Validation & Helper Scripts (`scripts/`)
- **`scripts/check-traits.sh`**: Validates device hardware traits configuration against the trait schema for all boards.
- **`scripts/check-kernel-config.sh`**: Validates kernel config fragments across all boards for duplicates, symbol syntax, and vendor enabler toggles.
- **`scripts/check-firmware.sh`**: Verifies all required firmware files (`CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` entries) exist in firmware directories.
- **`scripts/check-patches.sh`**: Ensures all `.patch` files on disk are referenced in build manifests (`APKBUILD`, Makefile, `series`).
- **`scripts/check-hashes.sh`**: Lints SHA-256 (64 hex chars) and SHA-512 (128 hex chars) string format integrity in Buildroot `.hash` files and `APKBUILD`s.
- **`scripts/update-device.sh`**: Generic push-and-apply OTA helper (stop UI → FTP upload → apply → reboot) for locally built update packages, e.g. the boot-profiler's instrumented initramfs packages. Normal OTA updates run **on-device** via `/usr/bin/update.sh`.
- **`scripts/fetch-asset.sh`**: Downloads a named release asset (`.img.zst` or `.tar.zst`) from the latest `testing` GitHub Release.
- **`scripts/remote-cmd.sh`**: Executes arbitrary shell commands on target device over telnet using `target_ip` from `deploy.cfg`.
- **`scripts/remote-upload.sh`**: Uploads a local file to the target device over FTP.

---

## 3. Developer Command Utilities (`Justfile`)

All local developer commands are managed via `Justfile` and executed with `just`:

| Recipe | What it checks | Shell / Tool | Notes |
|---|---|---|---|
| `just validate` | **Fast pre-commit gate** | `just` | Runs all fast quality gates listed below. |
| `just validate-ci` | **CI quality gate** | `just` | Runs `validate` plus `check-defconfigs` and `check-packages`. |
| `check-scripts` | `*.sh` files (all distros) | auto from shebang | Syntax (`sh -n`), shellcheck, exec bit. Excludes upstream Buildroot. |
| `check-apkbuilds` | `alpine/aports/**/APKBUILD` | `--shell=sh` | Syntax and shellcheck targeting ash; no shebang/exec check. |
| `check-openrc` | `minime/boards/*/overlay/etc/init.d/*` | `--shell=sh` | Shellcheck targeting ash; enforces executable bit. |
| `check-traits` | Device traits configuration | `scripts/check-traits.sh` | Validates board hardware traits config against schema. |
| `check-kernel-config` | Merged kernel config fragments | `scripts/check-kernel-config.sh` | Detects duplicate symbols, syntax errors, and orphaned vendor toggles. |
| `check-firmware` | Required firmware files | `scripts/check-firmware.sh` | Verifies `CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` files exist on disk. |
| `check-patches` | `.patch` files across repository | `scripts/check-patches.sh` | Ensures all `.patch` files are referenced in build manifests. |
| `check-hashes` | Package manifests `.hash` / `APKBUILD` | `scripts/check-hashes.sh` | Validates SHA-256 (64 hex) & SHA-512 (128 hex) string formats. |
| `check-git` | Git staged diff | `git diff --check` | Catches whitespace errors and unresolved merge conflict markers. |
| `just deploy <os> <board> <ui> [disk]` | Flash latest testing image | `fetch-asset.sh` + `dd` / `diskutil` | Fetches the latest `minime-<os>-<board>-<ui>.img.zst`, writes it to target disk, injects `wifi.cfg`, ejects card. Also accepts an explicit image path. Supports `deploy.cfg` + `minime` label guard. |
| `just remote <cmd> [ip]` | Run remote telnet command | `scripts/remote-cmd.sh` | Executes shell command on target device via telnet. Uses `target_ip` in `deploy.cfg`. The OTA update path is the **on-device** `/usr/bin/update.sh <minui|allium>` (e.g. `just remote "update.sh minui"`). |
| `just upload <file> [remote_filename] [ip]` | Upload a file to device | `scripts/remote-upload.sh` | Uploads a local file to the target device over FTP. |
| `just build-allium [target=musl]` | Build Allium locally | `cargo build` | Builds Allium binaries for `musl` (default) or `glibc`. |
| `just build-minui [target=musl]` | Build MinUI locally | `make system cores package` | Builds the MinUI binaries/cores for the `minime` platform. |
| `just install-hooks` | Git pre-commit hook | `.git/hooks/pre-commit` | Installs hook to run `just validate` before every commit. |

> `just fetch`, `just fetch-update`, `just update`, and `just check-version` are removed. OTA updates run **on-device** via `/usr/bin/update.sh <minui|allium>` (see the `live-test` skill). `just deploy` fetches the latest testing image on demand via `scripts/fetch-asset.sh`.
