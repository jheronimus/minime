# Infrastructure & Workflows (`docs/INFRA.md`)

This document describes all GitHub Actions (GA) CI/CD workflows, build scripts, entrypoints, and `Justfile` developer utilities in the Minime monorepo.

---

## 1. GitHub Actions Workflows (`.github/workflows/`)

### `alpine.yml` — Build Alpine Images
- **Trigger**: Push to `main` (matching `alpine/**` paths) or `workflow_dispatch`.
- **Purpose**: Cross-compiles Alpine Linux firmware images using Podman/Docker on `ubuntu-24.04-arm` runners.
- **Matrix**: Boards (`h700`, `rk3326`, `rk3566`) $\times$ UIs (`minui`, `allium`).
- **Artifacts**: Uploads `.img.xz` compressed disk images and build logs to the `testing` release.

### `buildroot.yml` — Build Buildroot Images
- **Trigger**: Push to `main` (matching `buildroot/**` or `alpine/board/**` paths) or `workflow_dispatch`.
- **Purpose**: Compiles minimal Buildroot firmware images on Ubuntu runners using ccache and download caching.
- **Matrix**: Boards (`rk3326`, `rk3566`, `h700`) $\times$ UIs (`minui`, `allium`).
- **Artifacts**: Uploads `.img.xz` compressed disk images to the `testing` release.

### `bootloader.yml` — Build Bootloaders
- **Trigger**: `workflow_dispatch` (manual or programmatically dispatched).
- **Purpose**: Clones upstream U-Boot and ARM Trusted Firmware (ATF), applies board patches and `uboot.config` fragments, and builds bootloader binaries (`u-boot-sunxi-with-spl.bin`, `idbloader.img`, `u-boot.itb`).
- **Automation**: Commits updated prebuilt binaries into `alpine/bootloader/<board>/` and automatically dispatches `alpine.yml` and `buildroot.yml` to trigger firmware image rebuilds.

### `update-packages.yml` — Automated Package Version Bumps
- **Trigger**: Scheduled cron job (daily) or `workflow_dispatch`.
- **Purpose**: Runs `scripts/uptodate/uptodate.py` to check for upstream releases of `retroarch`, `minui`, `allium`, `fatresize`, etc. Updates `APKBUILD`s, hash files, and defconfigs.

---

## 2. Repository Scripts & Entrypoints

### Orchestration & Build Scripts (`scripts/` and `alpine/scripts/`)
- **`scripts/prepare-linux.sh`**: Installs host build dependencies (`bison`, `flex`, `genimage`, `cpio`, `mtools`, `fatresize`, `parted`, `erofs-utils`, etc.) on Debian/Ubuntu hosts.
- **`scripts/build-bootloader.sh`**: Helper script invoked by `bootloader.yml` to compile ATF and U-Boot for `h700`, `rk3326`, or `rk3566`.
- **`scripts/uptodate/uptodate.py`**: Self-healing Python script that queries GitHub APIs for new release tags and computes SHA-512 hashes.
- **`scripts/update_kernel_version.py`**: Developer tool for updating kernel versions across board defconfigs.
- **`alpine/scripts/build.sh`**: Core Alpine image build engine. Compiles packages, stages rootfs, generates initramfs CPIO archives, and invokes `post-image.sh`.

### Image Assembly & Staging Scripts
- **`alpine/board/common/post-image.sh`**: Alpine post-image hook. Assembles `initramfs`, generates FAT32 `userdata.vfat` via `mkdosfs`, and runs `genimage`.
- **`buildroot/external/board/common/post-build.sh`**: Buildroot post-build script for copying runtime assets and init scripts into `$TARGET_DIR`.
- **`buildroot/external/board/common/post-image.sh`**: Buildroot post-image hook for packaging `minime-<board>.img.xz`.
- **`roms/install.sh`**: Asset installer script that maps and stages preloaded ROMs into the appropriate launcher directory structure (`MinUI` vs `Allium`).

---

## 3. Developer Command Utilities (`Justfile`)

All local developer commands are managed via `Justfile` and executed with `just`:

| Recipe | Description |
|---|---|
| `just validate` | **Fast pre-commit gate**. Runs shell script checks, `APKBUILD` ash validation, OpenRC init checks, traits validation, and git diff checks. |
| `just validate-ci` | **CI quality gate**. Runs `validate` plus defconfig merging (`check-defconfigs`) and package linting (`check-packages`). |
| `just fetch <os> <board> <ui>` | Downloads the specified release image from the `testing` release, decompresses it to `downloads/`, and offers an interactive prompt to deploy. |
| `just deploy <image> [disk]` | Flashes a firmware image to an SD card using `dd`, automatically injects `wifi.cfg` if present, and ejects the card. Supports `deploy.cfg` with `minime` label guard. |
| `just install-hooks` | Installs the repository git pre-commit hook to enforce `just validate` before every commit. |
