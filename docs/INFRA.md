# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions (GA) CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `alpine.yml` — Build Alpine Images
- **Trigger**: `workflow_run` of the Allium/MinUI UI workflows (completed, `main`); push to `main` on `minime/boards/**`, `minime/uboot/**`, `minime/build/**`, `minime/targets/alpine/**`, `src/**`, `roms/**`, `scripts/**`, `.github/workflows/alpine.yml`, `.github/actions/**`; or `workflow_dispatch`.
- **Purpose**: Cross-compiles Alpine Linux firmware images using Podman/Docker on `ubuntu-24.04-arm` runners.
- **Matrix**: Boards × UIs (`minui`, `allium`). Push builds `rk3566` + `h700`; `workflow_dispatch` can add `rk3326` (all three default on).
- **Artifacts**: Uploads `.img.xz` compressed disk images and `.tar.xz` update archives to the `testing` release.

### `buildroot.yml` — Build Buildroot Images
- **Trigger**: `workflow_run` of the Allium/MinUI UI workflows (completed, `main`); push to `main` on `minime/boards/**`, `minime/uboot/**`, `minime/build/**`, `minime/targets/buildroot/**`, `src/**`, `roms/**`, `scripts/**`, `.github/workflows/buildroot.yml`, `.github/actions/**`; or `workflow_dispatch`.
- **Purpose**: Compiles minimal Buildroot firmware images on Ubuntu runners using ccache and download caching. Runs `scripts/sync-kernel.sh` ("Check for updates") before building.
- **Matrix**: Boards × UIs (`minui`, `allium`). Push builds `rk3566` + `h700`; `workflow_dispatch` can add `rk3326` (h700 defaults off, rk3326/rk3566 on) and optionally cleans the board output first.
- **Artifacts**: Uploads `.img.xz` compressed disk images and `.tar.xz` update archives to the `testing` release.

### `bootloader.yml` — Build Bootloaders
- **Trigger**: `workflow_dispatch` (manual or programmatically dispatched).
- **Purpose**: Clones upstream U-Boot and ARM Trusted Firmware (ATF), applies board patches and `minime/uboot/config/uboot.config` fragments, and builds bootloader binaries (`u-boot-sunxi-with-spl.bin`, `idbloader.img`, `u-boot.itb`).
- **Automation**: Commits updated prebuilt binaries into `minime/uboot/out/<board>/`; the push lands under `minime/uboot/**`, which is in the push paths of `alpine.yml` and `buildroot.yml`, so the image rebuilds trigger automatically.

### `sync-kernel.yml` — Automated Kernel Version Sync
- **Trigger**: Daily schedule (cron); commits the bump directly to `main`.
- **Purpose**: Runs `scripts/sync-kernel.sh` to keep the kernel version synced between Alpine's `tinykernel` APKBUILD and Buildroot's custom kernel config.
- **Note**: `alpine.yml` and `buildroot.yml` also run `scripts/sync-kernel.sh` as a "Check for updates" step before building, so image builds always use the current Alpine-stable kernel regardless of the committed pin.

---

## 2. Repository Scripts & Entrypoints

### Orchestration & Build Scripts (`scripts/` and `minime/build/`)
- **`minime/build/mkimage.sh`**: Central image builder. Consumes compiled target artifacts (`kernel`, `initramfs.img`, `rootfs.erofs`, `.dtb`, `ui/`) and prebuilt U-Boot binaries, stages `userdata.vfat`, runs `genimage`, and compresses `minime-<target>-<board>.img.xz`.
- **`minime/build/mkupdate.sh`**: Central update package generator. Packages target artifacts into `minime-<target>-<board>[-<ui>].tar.xz` for live updates and distro switching.
- **`scripts/check-traits.sh`**: Validates device hardware traits configuration against the trait schema for all boards.
- **`scripts/check-kernel-config.sh`**: Validates kernel config fragments across all boards for duplicates, symbol syntax, and vendor enabler toggles.
- **`scripts/check-firmware.sh`**: Dynamically verifies that all required firmware files (`CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` entries) exist in firmware directories.
- **`scripts/check-patches.sh`**: Ensures all `.patch` files on disk are referenced in build manifests (`APKBUILD`, Makefile, `series`).
- **`scripts/check-hashes.sh`**: Lints SHA-256 (64 hex chars) and SHA-512 (128 hex chars) string format integrity in Buildroot `.hash` files and `APKBUILD`s.
- **`scripts/sync-kernel.sh`**: Bumps the kernel version and source `sha512sums` in Alpine's `tinykernel` APKBUILD and Buildroot's `common.config` to the latest Alpine-stable release.
- **`scripts/prepare-linux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.
- **`scripts/build-bootloader.sh`**: Helper script invoked by `bootloader.yml` to compile ATF and U-Boot for `h700`, `rk3326`, or `rk3566`.
- **`minime/targets/alpine/scripts/build.sh`**: Core Alpine image build engine. Compiles packages, stages rootfs, and generates erofs+initramfs.
- **`minime/targets/buildroot/external/scripts/post-build.sh`**: Buildroot post-build script for copying runtime assets and init scripts into `$TARGET_DIR`.
- **`minime/targets/buildroot/external/scripts/system-image.sh`**: Buildroot post-image hook that assembles `system.erofs` and the initramfs into `$(O)/images`.
- **`roms/install.sh`**: Asset installer script that maps and stages preloaded ROMs into the appropriate launcher directory structure (`MinUI` vs `Allium`).

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
| `just fetch <os> <board> <ui>` | Download release image | `curl` / `xz` | Fetches release image to `downloads/` and prompts for auto-deployment. |
| `just deploy <image> [disk]` | Flash image to SD card | `dd` / `diskutil` | Writes image to target disk, injects `wifi.cfg`, ejects card. Supports `deploy.cfg` + `minime` label guard. |
| `just install-hooks` | Git pre-commit hook | `.git/hooks/pre-commit` | Installs hook to run `just validate` before every commit. |
