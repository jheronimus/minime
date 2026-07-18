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

## Core Configs & Unification

Alpine owns all board assets (kernel configs, patches, genimage, boot.cmd, DTS, traits, uboot.config). Buildroot keeps only its own overlay, post-build.sh, post-image.sh, board.env, busybox.config, bios/, firmware/.

### Fragment ownership

If a config option is needed on every device, put it in a common fragment (`alpine/board/common/tiny-base.config` for kernel options, `buildroot/external/configs/minime_common.config` for Buildroot options). If it is only needed on one device, put it in that board's fragment (`alpine/board/<board>/tiny-<board>.config` or `buildroot/external/configs/minime_<board>.config`). GPU selection fragments: `alpine/board/common/tiny-panfrost.config` (Alpine) and `buildroot/external/board/common/tiny-libmali.config` (Buildroot). Never duplicate the same option across multiple board fragments; before adding it to a second board, move it to the common fragment.

- **Shared (`alpine/board/common/`)**:
  - [tiny-base.config](file:///Users/ilembitov/Projects/minime/alpine/board/common/tiny-base.config): Base kernel options (GPU-agnostic).
  - [tiny-panfrost.config](file:///Users/ilembitov/Projects/minime/alpine/board/common/tiny-panfrost.config): Panfrost GPU fragment for Alpine.
  - [genimage.cfg](file:///Users/ilembitov/Projects/minime/alpine/board/common/genimage.cfg): Shared RK3326/RK3566 partition layout.
- **Buildroot Shared (`buildroot/external/board/common/`)**:
  - [busybox.config](file:///Users/ilembitov/Projects/minime/buildroot/external/board/common/busybox.config): Shared BusyBox config.
  - [overlay/](file:///Users/ilembitov/Projects/minime/buildroot/external/board/common/overlay): System overlay (telnet/ftp, GPU driver init).
  - [tiny-libmali.config](file:///Users/ilembitov/Projects/minime/buildroot/external/board/common/tiny-libmali.config): Libmali GPU fragment for Buildroot.
  - [post-build.sh](file:///Users/ilembitov/Projects/minime/buildroot/external/board/common/post-build.sh): Common script (udev, network, board hooks).
  - [post-image.sh](file:///Users/ilembitov/Projects/minime/buildroot/external/board/common/post-image.sh): Shared packaging script.
- **Board Directories (`h700/`, `rk3326/`, `rk3566/`)**:
  - `board.env`: Env vars (default DTBs, images).
  - `boot.cmd`: Platform boot config.
  - `tiny-<board>.config`: Device-specific kernel config.
- **Genimage Configs (Partition Layouts)**:
  - H700: [h700/genimage.cfg](file:///Users/ilembitov/Projects/minime/alpine/board/h700/genimage.cfg) (MBR).
  - RK3326/RK3566: [common/genimage.cfg](file:///Users/ilembitov/Projects/minime/alpine/board/common/genimage.cfg) (GPT).

## Agent Directives (Buildroot Quirks)

- **Stale Target Cleanup**: Buildroot doesn't auto-clean `output/target/` when packages/configs change. Check/delete stale files (e.g. `S50dropbear`, `S50telnet` in `buildroot/output/target/etc/init.d/`) when modifying defconfigs/packages. If unsure, run `make clean` or purge target dir.
- **No Temporary Workarounds**: Fix local/runner states directly in the environment. Never add temporary configs, scripts, or hooks to build logic.
- **Container Image Rebuild**: `buildroot/container/Dockerfile` is only rebuilt when the `minime-builder` image is missing. If the Dockerfile changes, manually rebuild it locally.
- **Private Docs**: Keep docs in private directories, never in public repositories.
- **Never build locally**: Use GitHub Actions for all target builds.
- **Path and Restructuring Integrity**: When moving, renaming, or consolidating files or directories (e.g., board assets, source paths, packages), you MUST perform a repository-wide search (`grep`) for all references to the old paths in both `alpine/` and `buildroot/` directories (including Makefiles, package `.mk` files, configs, scripts, workflow files, and `APKBUILD`s) and update them concurrently.
- **Dual-Distro Co-equality**: Both Alpine and Buildroot are co-equal consumers of the shared assets. When modifying or consolidating a shared config/path, ensure the change is implemented in both build targets, verifying that neither target is left broken or using outdated paths.
- **Always update package versions** when working on custom packages like MinUI, retroarch-cores, etc.

## Commit Requirements for Remote Builds

Push changes to the respective branch on `jheronimus/minime` to trigger CI builds.

## Scripts & Git Exclusions

`scripts/` is strictly for:

1. Makefile/pipeline orchestration (`check_rebuild.py`, `prepare-linux.sh`).
2. Developer/agent utilities.

- **Git Exclusions**: Custom scripts/helpers (`test_otp.py`, `run_telnet.py`) MUST be in `.gitignore`. Track only Makefile dependencies.

## Remote Device Telnet Utilities

Telnet daemon runs on target console (`<target-ip>:23`).

- **`scripts/run_telnet.py`** (gitignored): Socket script for command execution with prompt detection, stdout streaming, and 120s timeout.
  - *Usage*: `python3 scripts/run_telnet.py "ls -la /mnt/sdcard"`

## CI Pipeline & Remote Runner

Builds compile on GitHub Actions runner.

- **Workflows**: `buildroot/` and `alpine/` workflows are located under `.github/workflows/`.
- **Sync Artifacts**: Fetch built images using the respective scripts.

## Pre-Commit Quality Gates (Strict Validation)

All warnings are blocking. Do not suppress/bypass; fix the root cause.

### 1. Buildroot Linting (`python3-magic` & `python3-flake8`)

```bash
python3 buildroot/buildroot/utils/check-package <modified_files>
```

### 2. Defconfig Validation

```bash
make defconfig BOARD=h700
make defconfig BOARD=rk3326
make defconfig BOARD=rk3566
```

- **Proactive Package Cleaning**: Run `make buildroot-<pkg>-dirclean BOARD=<board>` locally before committing.

### 3. Shellcheck

```bash
shellcheck --shell=sh --severity=warning <script_path>
```

### 4. Integrity Gates

- **Syntax**: `sh -n <script_path>`
- **Git**: `git diff --check`
- **Permissions**: `ls -l <script_path>` (must be executable)
- **Stamps**: `python3 scripts/check_rebuild.py`
