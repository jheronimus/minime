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
│   ├── alpine/         # Alpine target builder (aports, Makefile, container, configs, scripts)
│   └── buildroot/      # Buildroot target builder (external packages, Makefile, defconfigs, scripts)
└── genimage/           # Central Image & Update Packaging Pipeline
    ├── build-image.sh  # SD card bootable image builder (.img.xz)
    └── build-update.sh # Cross-distro update archive generator (.tar.gz)

src/                    # Shared Source Code Vaults
├── libmali/            # ARM Mali Bifrost/Utgard userspace libraries & shims
└── mali-kbase/         # ARM Mali Bifrost kernel module source (out-of-tree)

roms/                   # Preloaded public domain ROMs package
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

# Shared Assets (`minime/boards/`)

The `minime/boards/` directory is the single source of truth for all hardware definition files shared between Alpine and Buildroot target builders.

## 1. OpenRC Init Services (`minime/boards/common/overlay/etc/init.d/`)
Cross-distro OpenRC init scripts copied into the rootfs of both targets at build time:
- `bluetooth`: Dual-stack BlueZ daemon and Bluetooth manager.
- `fb-unblank`: Unblanks DRM/FB console and initializes display power.
- `ftpd`: Lightweight FTP server service.
- `gpudriver`: Dynamically loads Mali GPU kernel modules and sets device permissions.
- `modules`: Loads kernel modules specified in `/etc/modules`.
- `telnetd`: Remote debug shell daemon.
- `traits`: Parses hardware `platform.ini` and sets environment variables.
- `ui`: Launches the configured user interface launcher (`allium` or `minui`).
- `wifi`: WPA Supplicant and Wi-Fi interface initialization.
- `thermal-watchdog`: Board-specific CPU/GPU thermal watchdog daemon (in `minime/boards/rk3566/overlay/etc/init.d/`).

## 2. Shared Scripts & Boot Inits (`minime/boards/common/`)
- `initramfs-init.sh`: Early boot initramfs entrypoint script that mounts FAT32, loads `system.erofs`, and performs `switch_root`.
- `scripts/device.sh`: On-device hardware detection and DTB resolution script.
- `scripts/thermal-watchdog`: Temperature monitoring and throttling background script.
- `overlay/etc/sysctl.conf`: Kernel sysctl tuning (virtual memory, network buffers).
- `overlay/etc/wpa_supplicant.conf`: Default wireless network configuration template.

## 3. Kernel Configurations & Fragments (`minime/boards/`)
- `common/tiny-base.config`: Monorepo base Linux kernel configuration (common drivers, filesystems, EROFS, FAT32, ALSA).
- `common/tiny-libmali.config`: ARM Mali GPU kernel driver configuration fragment.
- `h700/tiny-h700.config`: Allwinner H700 SoC kernel configuration fragment (sunxi clock trees, AXP717 PMIC, DRM panel drivers).
- `rk3326/tiny-rk3326.config`: Rockchip RK3326 SoC kernel configuration fragment.
- `rk3566/tiny-rk3566.config`: Rockchip RK3566 SoC kernel configuration fragment.

## 4. Device Tree Sources (DTS) (`minime/boards/<board>/dts/`)
- `h700/dts/`: Device Trees for H700 devices (RG35XX SP, Plus, H, 28XX, 40XX).
- `rk3326/dts/`: Device Trees for RK3326 devices (`rk3326-anbernic-rg351p.dts`, `rk3326-anbernic-rg351mp.dts`).
- `rk3566/dts/`: Device Trees for RK3566 devices (RG353P, RG353V, RG353M, RG ARC).

## 5. Kernel & U-Boot Patches (`minime/boards/<board>/patches/`)
- `h700/patches/linux/`: H700 Linux kernel patches (AXP717, DRM panel, power management).
- `rk3326/patches/linux/`: RK3326 Linux kernel patches.
- `rk3566/patches/linux/`: RK3566 Linux kernel patches (panfrost, HDMI).
- `rk3566/patches/uboot/`: RK3566 U-Boot bootloader patches.

## 6. Partition & Bootloader Configurations
- `common/genimage.cfg`: Shared genimage specification for the FAT32 partition table.
- `h700/genimage.cfg`: H700-specific genimage specification detailing raw U-Boot SPL offsets.
- `h700/boot.env`: H700 U-Boot boot environment script (`bootargs`, kernel load address).
- `rk3326/boot.env`: RK3326 U-Boot boot environment script.
- `rk3566/boot.env`: RK3566 U-Boot boot environment script.

## 7. Board Firmware Blobs
- `common/firmware/`: Realtek Wi-Fi and Bluetooth firmware blobs (`rtl_bt/`, `rtw88/`).
- `h700/firmware/panels/`: Display panel initialization sequences for H700 devices.
- `rk3326/firmware/`: Wi-Fi USB dongle firmware blobs.

## 8. Hardware Traits (`minime/boards/<board>/traits/`)
Immutable hardware capability profiles copied to `/usr/share/minime/traits/`:
- `platform.ini`: General system traits (SoC architecture, GPU driver flavor).
- `audio.ini`: Audio card and mixer definitions.
- `display.ini`: Display resolution, refresh rates, and brightness control paths.
- `controls.ini`: Input device mapping and button definitions.

---

# Bootloaders (`minime/uboot/`)

Contains U-Boot configurations, patches, and prebuilt binaries:
- `config/`: U-Boot defconfigs (`uboot.config`, `ddr3.defconfig`, `bootloader-*.config`).
- `patches/`: U-Boot and ARM Trusted Firmware (ATF) source patches.
- `out/`: Prebuilt bootloader binaries:
  - `h700/`: `u-boot-sunxi-with-spl.bin`, `u-boot-sunxi-with-spl-ddr3.bin`
  - `rk3326/`: `idbloader.img`, `u-boot.itb`
  - `rk3566/`: `idbloader.img`, `u-boot.itb`, `rkbin/bl31.elf`, `rkbin/rk3566_ddr_1056MHz_v1.25.bin`

---

# Target Software Builders

## Alpine Target Builder (`minime/targets/alpine/`)

Building Alpine Linux firmware for Minime:

- **`Makefile`**: Main entrypoint for Alpine builds (`make image BOARD=<board> UI=<ui>`). Handles container orchestration, volume mounts, and invocation of `build.sh`.
- **`scripts/build.sh`**: Core orchestration script that:
  1. Fetches and validates the official Alpine minirootfs tarball.
  2. Compiles `tinykernel` APK (kernel `Image`, modules, and DTBs).
  3. Prepares chroot environment, bind-mounts pseudo filesystems (`proc`, `sys`, `dev`), installs package dependencies (`aports/`), and installs board traits and OpenRC overlays.
  4. Terminates chroot background processes, cleans bind mounts, and verifies empty mountpoints.
  5. Packages `${TARGET_OUT}/system.erofs` using `mkfs.erofs -z lz4hc`.
  6. Assembles the custom initramfs (`initramfs.img`).
  7. Invokes `${MINIME_ROOT}/minime/genimage/build-image.sh` and `build-update.sh`.
- **`container/Dockerfile`**: Build environment container specification for Alpine (`arm64`, `abuild`, `squashfs-tools`, `erofs-utils`, `genimage`).
- **`configs/`**: Build configuration settings and target board overrides.
- **`out/<board>/`**: Staging directory for compiled `Image`, `initramfs.img`, `system.erofs`, `.dtb` files, and the final `minime-alpine-<board>.img.xz`.

## Buildroot Target Builder (`minime/targets/buildroot/`)

Building Buildroot firmware for Minime:

- **`Makefile`**: Main entrypoint for Buildroot builds (`make image BOARD=<board> UI=<ui>`). Handles container orchestration, ccache mounting, and execution of Buildroot `make`.
- **`external/Config.in`**: Buildroot external tree package menu declarations.
- **`external/external.mk`**: Buildroot external tree Makefile rules. Hooks Linux kernel compilation, copies custom DTS files from `${MINIME_ROOT}/minime/boards/<board>/dts/`, and stages firmware blobs.
- **`external/external.desc`**: External tree metadata descriptor (`name: MINIME`).
- **`external/configs/`**: Target configuration fragments:
  - `common.config`: Base Buildroot configuration (musl/glibc, OpenRC, busybox, alsa, wpa_supplicant, bluez).
  - `h700.config`: H700 SoC buildroot config fragment.
  - `rk3326.config`: RK3326 SoC buildroot config fragment.
  - `rk3566.config`: RK3566 SoC buildroot config fragment.
  - `allium.config`: Allium UI launcher config fragment.
  - `minui.config`: MinUI UI launcher config fragment.
- **`scripts/post-build.sh`**: Buildroot post-build script that copies OpenRC services from `${MINIME_ROOT}/minime/boards/common/overlay` into Buildroot target rootfs.
- **`scripts/post-image.sh`**: Buildroot post-image script that constructs custom initramfs and invokes `${MINIME_ROOT}/minime/genimage/build-image.sh` and `build-update.sh`.
- **`out/<board>/`**: Target output directory.

---

# Central Packager (`minime/genimage/`)

- **`build-image.sh`**: Consumes output artifacts (`Image`, `initramfs.img`, `system.erofs`, `.dtb`s) from `minime/targets/<target>/out/<board>/`, constructs `userdata.vfat`, stages prebuilt bootloaders from `${MINIME_ROOT}/minime/uboot/out/<board>/`, runs `genimage`, and compresses final `minime-<target>-<board>.img.xz`.
- **`build-update.sh`**: Consumes output artifacts from `minime/targets/<target>/out/<board>/` and emits `minime-update-<target>-<board>.tar.gz` for cross-distro updates and live target switching.
