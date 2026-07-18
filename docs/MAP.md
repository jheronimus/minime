# monorepo Map: Consolidated Monorepo Structure

Overview of shared and distro-specific assets across the Alpine and Buildroot trees.

# Shared files

## Board firmware blobs
All firmware consolidated under `alpine/board/*/firmware/`. Buildroot references it directly from there.
- `alpine/board/common/firmware/` — Common Realtek Wi-Fi/BT (rtl_bt, rtw88)
- `alpine/board/h700/firmware/panels/` — H700 MIPI DPI panel init
- `alpine/board/rk3326/firmware/` — RK3326 USB dongle Wi-Fi/BT drivers

## Prebuilt bootloader binaries
Under `alpine/bootloader/`. Built by `.github/workflows/bootloader.yml`. Both Alpine and Buildroot use these for image assembly.
- H700: `u-boot-sunxi-with-spl.bin`
- RK3326: `idbloader.img`, `u-boot.itb`
- RK3566: `idbloader.img`, `u-boot.itb`, `rkbin/bl31.elf`, `rkbin/rk3566_ddr_1056MHz_v1.25.bin`

## `config/cores.cfg`
- Source of truth: Alpine tree (`alpine/board/common/config/cores.cfg`).
- Buildroot packages/scripts reference it directly from the Alpine path. No duplicates exist.

## Source code (`src/`)
- `src/bootsplash/` — bootsplash package source
- `src/libmali/` — Mali GLES userspace driver blobs and headers
- `src/mali-kbase/` — Mali kernel driver out-of-tree module

## Traits (`platform.ini` + device `.inis`)
Source of truth is Alpine tree (`alpine/board/*/traits/`). Buildroot's `post-build.sh` copies traits directly from there.

## Boot scripts (`boot.cmd`) + DTS overlays
Source of truth is Alpine tree (`alpine/board/*/`). Buildroot compiles them from the Alpine path.

## U-Boot configs (`uboot.config`)
Source of truth is Alpine tree (`alpine/board/*/uboot.config`). Buildroot references them from there.

## Genimage configs
Source of truth is Alpine tree (`alpine/board/`). Buildroot uses the same files passed via `-c`.

# Alpine-specific

## Init scripts (OpenRC)
All under `alpine/aports/minime-overlay/files/etc/init.d/`. Uses OpenRC syntax.

## Overlay configs
All under `alpine/aports/minime-overlay/files/`.

## World configs (`alpine/configs/`)
Alpine package sets (world-common, world-<board>).

## Validation scripts
- `alpine/board/common/check-traits.sh` — traits validator.
- `alpine/board/rk3326/first-boot-probe.sh` — rk3326 initramfs probe.

## Build infrastructure
- `alpine/Makefile` — Alpine build orchestrator
- `alpine/scripts/build.sh` — Alpine image builder
- `alpine/container/Dockerfile` — builder container

# Buildroot-specific

## Init scripts (Busybox S##)
All under `buildroot/external/board/common/overlay/etc/init.d/`.

## Overlay configs
All under `buildroot/external/board/common/overlay/`.

## Defconfigs (`buildroot/external/configs/`)
Buildroot configurations (minime_common.config, minime_<board>.config).

## BusyBox config
`buildroot/external/board/common/busybox.config` — BusyBox applet selection.

## GPU kernel fragment
`buildroot/external/board/common/tiny-libmali.config` — kernel fragment for proprietary libmali.
## Build infrastructure
- `buildroot/Makefile` — Buildroot build orchestrator
- `buildroot/external/board/common/post-build.sh` — Buildroot post-build script
- `buildroot/external/board/common/post-image.sh` — Buildroot post-image script
- `buildroot/external/external.mk`, `external.desc`, `Config.in` — Buildroot external tree hooks
