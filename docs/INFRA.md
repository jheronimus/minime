# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions (GA) CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `alpine.yml` — Build Alpine Images
- **Trigger**: Push to `main` (matching `minime/boards/**`, `minime/targets/alpine/**`, `minime/genimage/**`) or `workflow_dispatch`.
- **Purpose**: Cross-compiles Alpine Linux firmware images using Podman/Docker on `ubuntu-24.04-arm` runners.
- **Matrix**: Boards (`h700`, `rk3326`, `rk3566`) $\times$ UIs (`minui`, `allium`).
- **Artifacts**: Uploads `.img.xz` compressed disk images and build logs to the `testing` release.

### `buildroot.yml` — Build Buildroot Images
- **Trigger**: Push to `main` (matching `minime/boards/**`, `minime/targets/buildroot/**`, `minime/genimage/**`) or `workflow_dispatch`.
- **Purpose**: Compiles minimal Buildroot firmware images on Ubuntu runners using ccache and download caching.
- **Matrix**: Boards (`rk3326`, `rk3566`, `h700`) $\times$ UIs (`minui`, `allium`).
- **Artifacts**: Uploads `.img.xz` compressed disk images to the `testing` release.

### `bootloader.yml` — Build Bootloaders
- **Trigger**: `workflow_dispatch` (manual or programmatically dispatched).
- **Purpose**: Clones upstream U-Boot and ARM Trusted Firmware (ATF), applies board patches and `minime/uboot/config/uboot.config` fragments, and builds bootloader binaries (`u-boot-sunxi-with-spl.bin`, `idbloader.img`, `u-boot.itb`).
- **Automation**: Commits updated prebuilt binaries into `minime/uboot/out/<board>/` and automatically dispatches `alpine.yml` and `buildroot.yml` to trigger firmware image rebuilds.

### `update-packages.yml` — Automated Package Version Bumps
- **Trigger**: Scheduled cron job (daily) or `workflow_dispatch`.
- **Purpose**: Runs `scripts/uptodate/uptodate.py` to check for upstream releases of `retroarch`, `minui`, `allium`, `fatresize`, etc. Updates `APKBUILD`s, hash files, and defconfigs.

---

## 2. Repository Scripts & Entrypoints

### Orchestration & Build Scripts (`scripts/` and `minime/genimage/`)
- **`minime/genimage/genimage.sh`**: Central image builder. Consumes compiled target artifacts (`kernel`, `initramfs.img`, `rootfs.erofs`, `.dtb`, `ui/`) and prebuilt U-Boot binaries, stages `userdata.vfat`, runs `genimage`, and compresses `minime-<target>-<board>.img.xz`.
- **`minime/genimage/genupdate.sh`**: Central update package generator. Packages target artifacts into `minime-update-<target>-<board>.tar.gz` for live updates and distro switching.
- **`scripts/check-kernel-config.py`**: Validates kernel config fragments across all boards for duplicates, symbol syntax, and vendor enabler toggles.
- **`scripts/check-firmware.py`**: Dynamically verifies that all required firmware files (`CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` entries) exist in firmware directories.
- **`scripts/check-patches.py`**: Ensures all `.patch` files on disk are referenced in build manifests (`APKBUILD`, Makefile, `series`).
- **`scripts/check-hashes.py`**: Lints SHA-256 (64 hex chars) and SHA-512 (128 hex chars) string format integrity in Buildroot `.hash` files and `APKBUILD`s.
- **`scripts/prepare-linux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.
- **`scripts/build-bootloader.sh`**: Helper script invoked by `bootloader.yml` to compile ATF and U-Boot for `h700`, `rk3326`, or `rk3566`.
- **`minime/targets/alpine/scripts/build.sh`**: Core Alpine image build engine. Compiles packages, stages rootfs, and invokes `genimage.sh`.
- **`minime/targets/buildroot/scripts/post-build.sh`**: Buildroot post-build script for copying runtime assets and init scripts into `$TARGET_DIR`.
- **`minime/targets/buildroot/scripts/post-image.sh`**: Buildroot post-image hook for packaging images via `genimage.sh`.
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
| `check-openrc` | `alpine/aports/**/files/etc/init.d/*` | `--shell=sh` | Shellcheck targeting ash; enforces executable bit. |
| `check-traits` | Device traits configuration | `scripts/check-traits.sh` | Validates board hardware traits config against schema. |
| `check-kernel-config` | Merged kernel config fragments | `scripts/check-kernel-config.py` | Detects duplicate symbols, syntax errors, and orphaned vendor toggles. |
| `check-firmware` | Required firmware files | `scripts/check-firmware.py` | Verifies `CONFIG_EXTRA_FIRMWARE` and DTS `firmware-name` files exist on disk. |
| `check-patches` | `.patch` files across repository | `scripts/check-patches.py` | Ensures all `.patch` files are referenced in build manifests. |
| `check-hashes` | Package manifests `.hash` / `APKBUILD` | `scripts/check-hashes.py` | Validates SHA-256 (64 hex) & SHA-512 (128 hex) string formats. |
| `check-git` | Git staged diff | `git diff --check` | Catches whitespace errors and unresolved merge conflict markers. |
| `just fetch <os> <board> <ui>` | Download release image | `curl` / `xz` | Fetches release image to `downloads/` and prompts for auto-deployment. |
| `just deploy <image> [disk]` | Flash image to SD card | `dd` / `diskutil` | Writes image to target disk, injects `wifi.cfg`, ejects card. Supports `deploy.cfg` + `minime` label guard. |
| `just install-hooks` | Git pre-commit hook | `.git/hooks/pre-commit` | Installs hook to run `just validate` before every commit. |
