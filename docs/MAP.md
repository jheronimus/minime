# Monorepo Map: Centralized Minime Architecture

Overview of shared hardware assets, target distro builders, bootloaders, image packaging, shared source vaults, and path resolution contracts under `minime/`.

The single source of truth for all board assets, OpenRC services, DTS files, kernel patches, firmware, and traits is the `minime/boards/` directory.

---

# Architecture Overview

```
minime/
├── boards/             # Single Source of Truth for Hardware
│   ├── common/         # Shared OpenRC init scripts, sysctl, wifi config, device.sh, initramfs init
│   ├── h700/           # H700 DTS, patches, traits, boot.env, genimage.cfg
│   ├── rk3326/         # RK3326 DTS, patches, traits, boot.env, genimage.cfg
│   └── rk3566/         # RK3566 DTS, patches, traits, boot.env, genimage.cfg
├── uboot/              # Bootloader definitions & prebuilt binaries
│   ├── config/         # uboot.config, ddr3.defconfig, bootloader-*.config
│   ├── patches/        # U-Boot & ATF patches
│   └── out/            # Prebuilt bootloader binaries (h700, rk3326, rk3566, rkbin)
├── targets/            # Target Software Builders
│   ├── alpine/         # Alpine target builder (aports, Makefile, container, scripts)
│   └── buildroot/      # Buildroot target builder (external packages, Makefile, defconfigs, scripts)
└── genimage/           # Central Image & Update Packaging Pipeline
    ├── build-image.sh  # SD card bootable image builder (.img.xz)
    └── build-update.sh # Cross-distro update archive generator (.tar.gz)

src/                    # Shared Source Code Vaults
├── libmali/            # ARM Mali Bifrost/Utgard userspace libraries & shims
└── mali-kbase/         # ARM Mali Bifrost kernel module source (out-of-tree)

roms/                   # Preloaded open-source ROMs package
docs/                   # ADRs (adr/) and Research Specs (research/)
.github/workflows/      # CI Workflows (alpine.yml, buildroot.yml, bootloader.yml, container.yml)
```

---

# Path Architecture & Variable Contract

To ensure dual-distro co-equality and prevent path drift across Alpine and Buildroot target builders:

1. **`MINIME_ROOT`**: Absolute path to the monorepo root directory (`/workspace` inside containers, or repository root on host).
   - **Shared Board Assets**: `${MINIME_ROOT}/minime/boards/`
   - **Shared Image Packagers**: `${MINIME_ROOT}/minime/genimage/`
   - **Prebuilt Bootloaders**: `${MINIME_ROOT}/minime/uboot/`
   - **Shared Local Sources**: `${MINIME_ROOT}/src/` and `${MINIME_ROOT}/roms/`
2. **Target Roots (`ALPINE_ROOT` / `BUILDROOT_ROOT`)**:
   - `ALPINE_ROOT`: `${MINIME_ROOT}/minime/targets/alpine`
   - `BUILDROOT_ROOT`: `${MINIME_ROOT}/minime/targets/buildroot`
   - Target-local assets (`aports/`, `external/`, `configs/`, target scripts) resolve relative to their respective target root.

---

# Key Shared Assets

## Board Firmware Blobs
- `minime/boards/common/firmware/` — Common Realtek Wi-Fi/BT (rtl_bt, rtw88)
- `minime/boards/h700/firmware/panels/` — H700 MIPI DPI panel init
- `minime/boards/rk3326/firmware/` — RK3326 USB dongle Wi-Fi/BT drivers

## Bootloaders (`minime/uboot/`)
- Prebuilt binaries in `minime/uboot/out/<board>/`. Rebuilt via `scripts/build-bootloader.sh` and `.github/workflows/bootloader.yml`.
- `h700/`: `u-boot-sunxi-with-spl.bin`, `u-boot-sunxi-with-spl-ddr3.bin`
- `rk3326/`: `idbloader.img`, `u-boot.itb`
- `rk3566/`: `idbloader.img`, `u-boot.itb`, `rkbin/bl31.elf`, `rkbin/rk3566_ddr_1056MHz_v1.25.bin`

## OpenRC Init Services
All under `minime/boards/common/overlay/etc/init.d/`:
- `wifi`, `ui`, `traits`, `bluetooth`, `fb-unblank`, `ftpd`, `modules`, `telnetd`, `gpudriver`.

## DTS Source Files
- `minime/boards/h700/dts/` — H700 Allwinner boards
- `minime/boards/rk3326/dts/` — RK3326 boards
- `minime/boards/rk3566/dts/` — RK3566 boards

## Kernel & U-Boot Patches
- `minime/boards/h700/patches/linux/`
- `minime/boards/rk3326/patches/linux/`
- `minime/boards/rk3566/patches/linux/`
- `minime/boards/rk3566/patches/uboot/`

## Traits (`platform.ini` + device `.inis`)
- `minime/boards/<board>/traits/`

---

# Target Software Builders

## Alpine Target (`minime/targets/alpine/`)
- Cross-compiles musl-based packages (`aports/`), builds tinykernel, installs OpenRC services from `minime/boards/common/overlay/`, cleans bind-mounted pseudo filesystems (`proc`, `sys`, `dev`), and outputs `Image`, `initramfs.img`, `system.erofs`, `.dtb`, and `ui/` to `minime/targets/alpine/out/<board>/`.

## Buildroot Target (`minime/targets/buildroot/`)
- Cross-compiles glibc-based packages (`external/package/`), builds kernel, installs OpenRC services from `minime/boards/common/overlay/`, and outputs `Image`, `initramfs.img`, `system.erofs`, `.dtb`, and `ui/` to `minime/targets/buildroot/out/<board>/`.

---

# Central Packager (`minime/genimage/`)

- **`build-image.sh`**: Consumes output artifacts from `minime/targets/<target>/out/<board>/`, constructs `userdata.vfat`, stages prebuilt bootloaders from `${MINIME_ROOT}/minime/uboot/out/<board>/`, runs `genimage`, and compresses final `minime-<target>-<board>.img.xz`.
- **`build-update.sh`**: Consumes output artifacts from `minime/targets/<target>/out/<board>/` and emits `minime-update-<target>-<board>.tar.gz` for cross-distro updates and live target switching.
