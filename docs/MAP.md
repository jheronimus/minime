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
├── build/              # Central Packaging Pipeline
│   ├── mkimage.sh      # SD card bootable image builder (.img.zst)
│   ├── mkupdate.sh     # Cross-distro update archive generator (.tar.gz)
│   ├── genassets.sh    # UI payload downloader
│   └── container/      # Multi-arch shared packager container (genimage + mtools)

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
   - **Shared Image Packagers**: `${MINIME_ROOT}/minime/build/`
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
- `dropbear`: SSH server (not enabled by default; opt-in via config marker).
- `fb-unblank`: Unblanks DRM/FB console and initializes display power.
- `ftpd`: Lightweight FTP server service.
- `gpudriver`: Dynamically loads Mali GPU kernel modules and sets device permissions.
- `logger`: Persistent per-boot kernel + syslog capture under `.minime/logs/`; hosts the thermal monitor worker (derives thresholds from the zone's `trip_point_*`, ADR 0014).
- `modules`: Loads kernel modules specified in `/etc/modules`.
- `telnetd`: Remote debug shell daemon.
- `traits`: Emits the merged device traits file at `/mnt/sdcard/.minime/traits` (cascades `platform.ini` + device `parent=` chain) for UIs to consume.
- `ui`: Launches the configured user interface launcher (`allium` or `minui`).
- `wifi`: iwd (Internet Wireless Daemon) Wi-Fi connectivity + DHCP.

## 2. Shared Scripts & Boot Inits (`minime/boards/common/`)
- `initramfs-init.sh`: Early boot initramfs entrypoint script that mounts FAT32, loads `system.erofs`, and performs `switch_root`.
- `scripts/device.sh`: On-device hardware detection and DTB resolution script.
- `scripts/log-boot.sh`: Append a timestamped marker to the current boot's `boot.log`.
- `scripts/collect-diagnostics.sh`: Bundle logs + dmesg + config into a diagnostics tarball.
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
- `platform.ini`: SoC-wide defaults (screen/backlight, CPU clocks + thermal, GPU, audio, input device names, keycodes, power, USB, storage). Any key may be overridden at device level.
- `devices/<device>.ini`: Per-device traits (identity, screen geometry, HDMI, touch, rumble, wireless). Panel-revision variants inherit from a base device via a `parent=` key.
- At boot `init.d/traits` merges `platform.ini` → parent chain → device file into `/mnt/sdcard/.minime/traits` (last-wins for duplicated keys).

See `docs/adr/0012-traits-schema.md` for the full section/key reference.

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

- **`Makefile`**: Entrypoint for Alpine builds. Two-step build convention:
  - `make components BOARD=<board> UI=<ui>` — compilation in container (minirootfs, APKs, rootfs, erofs, initramfs).
  - `make image BOARD=<board> UI=<ui>` — runs `genassets.sh` + `mkimage.sh` + `mkupdate.sh` in packager container.
- **`scripts/build.sh`**: Core build script with subcommands:
  - `components` (default): resolve_minirootfs → build_local_apks → assemble_rootfs → build_system_image
  - `system-image`: erofs + initramfs only (second container invocation of `make components`)
  - `minirootfs`, `apks`, `rootfs`: individual steps for development
- **`container/Dockerfile`**: Build environment container (`arm64`, `abuild`, `erofs-utils`, `genimage`, `mtools`).
- **`configs/`**: Build configuration and world package lists per board.
- **`aports/`**: Local APK build recipes (tinykernel, fatresize, drkhrse-miyoo-bezels).
- **`out/<board>/`**: Staging directory for `Image`, `initramfs.img`, `system.erofs`, `.dtb` files, and final `minime-alpine-<board>-<ui>.img.zst` (plus `minime-alpine-<board>-<ui>.tar.zst` OTA package).

## Buildroot Target Builder (`minime/targets/buildroot/`)

Building Buildroot firmware for Minime:

- **`Makefile`**: Entrypoint for Buildroot builds. Two-step build convention:
  - `make components BOARD=<board> UI=<ui>` — compilation in container (defconfig, full Buildroot build).
  - `make image BOARD=<board> UI=<ui>` — runs `genassets.sh` + `mkimage.sh` + `mkupdate.sh` in packager container.
- **`scripts/build.sh`**: Build wrapper with subcommands:
  - `components` (default): defconfig → make → copy_images
  - `defconfig`: merge config fragments only
- **`external/`**: Buildroot external tree:
  - `external/Config.in`: Package menu declarations.
  - `external/external.mk`: Makefile rules. Hooks kernel compilation, copies DTS, stages firmware.
  - `external/external.desc`: External tree metadata (`name: MINIME`).
  - `external/configs/`: Config fragments: `common.config`, `<board>.config`, `<ui>.config`.
  - `external/scripts/post-build.sh`: Copies OpenRC services, traits, firmware into rootfs.
  - `external/scripts/system-image.sh`: Builds system.erofs and initramfs.
  - `external/package/`: Custom packages (fatresize, libmali, mali-kbase, drkhrse-miyoo-bezels).
- **`container/Dockerfile`**: Build environment container (`debian:bookworm-slim`, `genimage`, `mtools`, `erofs-utils`).
- **`out/<board>/`**: Target output directory.

---

# Central Packager (`minime/build/`)

- **`mkimage.sh`**: Consumes output artifacts (`Image`, `initramfs.img`, `system.erofs`, `.dtb`s) from `minime/targets/<target>/out/<board>/`, constructs `userdata.vfat`, stages prebuilt bootloaders from `${MINIME_ROOT}/minime/uboot/out/<board>/`, runs `genimage`, and compresses final `minime-<target>-<board>.img.zst`.
- **`mkupdate.sh`**: Consumes output artifacts from `minime/targets/<target>/out/<board>/` and emits `minime-<target>-<board>[-<ui>].tar.zst` for cross-distro updates and live target switching.

---

# Build Convention

Both Alpine and Buildroot follow a two-step build convention:

```
make components  →  build.sh  (compilation in builder container)
make image       →  genassets.sh + mkimage.sh + mkupdate.sh  (packaging in shared packager container)
```

| Step | Alpine | Buildroot | Runs |
|------|--------|-----------|------|
| `make components` | `build.sh components` | `build.sh components` | In builder container |
| `make image` | `genassets.sh` + `mkimage.sh` + `mkupdate.sh` | `genassets.sh` + `mkimage.sh` + `mkupdate.sh` | In shared packager container |

**Rules:**
- `build.sh` does compilation only. No image packaging.
- `mkimage.sh` does image packaging only. No compilation.
- `mkupdate.sh` does update archive generation. No compilation.
- The Makefile orchestrates the two steps. CI calls `make components` then `make image` separately.

---

# Modification Guide

## Adding a new board

1. Create `minime/boards/<board>/` directory with:
   - `boot.env` — U-Boot boot arguments
   - `dts/` — Device Tree Source files
   - `patches/linux/` — Kernel patches (if needed)
   - `traits/` — Hardware trait files (`platform.ini`, `devices/<device>.ini`)
2. Add board config fragments:
   - `minime/boards/<board>/tiny-<board>.config` — kernel config fragment
   - `minime/targets/alpine/configs/world-<board>` — Alpine package list
   - `minime/targets/buildroot/external/configs/<board>.config` — Buildroot config fragment
3. Add bootloader binaries to `minime/uboot/out/<board>/`
4. Update `SUPPORTED_BOARDS` in both `minime/targets/alpine/Makefile` and `minime/targets/buildroot/Makefile`
5. Update CI matrix in `.github/workflows/alpine.yml` and `.github/workflows/buildroot.yml`

## Adding a new kernel option

1. Add to `minime/boards/common/tiny-base.config` (if shared) or `minime/boards/<board>/tiny-<board>.config` (if board-specific)
2. For Buildroot: also add to `minime/targets/buildroot/external/configs/common.config` or `<board>.config`
3. Run `just validate` to verify config fragments are valid

## Adding a new OpenRC service

1. Create the script in `minime/boards/common/overlay/etc/init.d/<service>`
2. Add the service to the `for svc in ...` loop in `minime/targets/buildroot/external/scripts/post-build.sh`
3. Add runlevel symlinks as needed (boot vs default)
4. Alpine automatically picks up everything from the common overlay

## Adding a new package

**Alpine**: Create `minime/targets/alpine/aports/<package>/APKBUILD` and add to `ALPINE_PKGS` in `build.sh`.

**Buildroot**: Create `minime/targets/buildroot/external/package/<package>/` with `Config.in`, `<package>.mk`, and add to `external/Config.in`.
