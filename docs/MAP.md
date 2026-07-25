# monorepo Map: Consolidated Monorepo Structure

Overview of shared and distro-specific assets across the Alpine and Buildroot trees.

Alpine is the **canonical source** for all shared configuration, init scripts, and board overlays. Buildroot copies them at build time via `post-build.sh`.

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

## Source code (`src/`)
- `src/bootsplash/` — bootsplash package source
- `src/libmali/` — Mali GLES userspace driver blobs and headers
- `src/mali-kbase/` — Mali kernel driver out-of-tree module

## OpenRC init scripts
All under `alpine/board/common/overlay/etc/init.d/`. **Single source of truth** — Buildroot copies them verbatim via `post-build.sh` (except `panfrost`, which Buildroot replaces with `gpudriver`).
- `wifi` — wpa_supplicant + udhcpc
- `ui` — UI launcher
- `traits` — immutable trait builder
- `bluealsa` — Bluetooth A2DP audio
- `bluetooth` — Bluetooth daemon
- `bootsplash` — animated boot splash
- `dbus` — D-Bus system bus
- `fb-unblank` — unblank framebuffer
- `ftpd` — anonymous FTP to SD card
- `modules` — load kernel modules
- `telnetd` — passwordless telnet
- `gpudriver` — Mali GPU driver (Buildroot-only, in `buildroot/external/board/common/overlay/etc/init.d/`)

Board-specific init scripts live in `alpine/board/<board>/overlay/etc/init.d/` and are copied by the board's `post-build.sh`:
- `alpine/board/rk3566/overlay/etc/init.d/thermal-watchdog` — RK3566 thermal watchdog

## Overlay configs
### Canonical shared overlay (`alpine/board/common/overlay/`)
All shared system configuration lives here. Buildroot copies specific files at build time.
- `etc/hostname`, `etc/hosts` — hostname config
- `etc/fstab` — Alpine rootfs mount table (Buildroot has its own at `buildroot/external/board/common/overlay/etc/fstab`)
- `etc/modules-load.d/wifi.conf` — WiFi module list (copied by Buildroot)
- `etc/modprobe.d/rtw88.conf` — rtw88 driver options (copied by Buildroot)
- `etc/sysctl.d/00-minime.conf` — sysctl tuning (copied by Buildroot)
- `etc/udev/rules.d/50-panfrost.rules` — Panfrost udev rules (Alpine-only; Buildroot uses `50-mali.rules`)
- `usr/bin/autologin` — autologin binary

### Buildroot-only overlay (`buildroot/external/board/common/overlay/`)
Files unique to Buildroot, not present in Alpine:
- `etc/init.d/gpudriver` — Mali GPU driver service
- `etc/udev/rules.d/50-mali.rules` — Mali udev rules
- `etc/default/seedrng` — RNG seed config
- `etc/fstab` — Buildroot mount table (overrides Alpine's)

## Shared runtime scripts (`alpine/board/common/scripts/`)
Canonical home for cross-distro runtime scripts installed into `/usr/share/minime/scripts/`:
- `device.sh` — Device configuration (`device.cfg`) builder (`init-cfg`), reader (`get`), and writer (`set`).
- `thermal-watchdog` — Userspace thermal watchdog for RK3566 (temperature monitoring + logging). Installed by both Alpine (`build.sh`) and Buildroot (`rk3566/post-build.sh`).

## Shared config files (copied by Buildroot)
These files are canonical in Alpine's overlay. Buildroot copies them at build time:
- `wifi.conf` — WiFi module load list
- `rtw88.conf` — rtw88 driver options
- `00-minime.conf` — sysctl tuning

## Traits (`platform.ini` + device `.inis`)
Source of truth is Alpine tree (`alpine/board/*/traits/`). Buildroot's `post-build.sh` copies traits directly from there.

## UI integration contract (`.minime/ui.env`)
Source of truth is UI packages (`alpine/aports/minui/`, `alpine/aports/allium/`, `buildroot/external/package/minui/`). Staged to `/mnt/sdcard/.minime/ui.env` on SD card image assembly.

## Boot scripts (`boot.cmd`) + DTS overlays
Source of truth is Alpine tree (`alpine/board/*/`). Buildroot compiles them from the Alpine path.

## DTS source files (`alpine/board/*/dts/`)
Custom device tree source files copied into the kernel tree during `tinykernel/APKBUILD` build. Used for boards whose DTS is not yet upstream.
- `alpine/board/h700/dts/` — H700 Allwinner boards (rg35xx, rg40xx, rg28xx, rgcubexx, etc.)
- `alpine/board/rk3326/dts/` — RK3326 boards (rg351p, rg351mp)

## Kernel and U-Boot patches (`alpine/board/*/patches/`)
Per-board patch series applied during kernel (via `tinykernel/APKBUILD`) and Buildroot (via `BR2_GLOBAL_PATCH_DIR`) builds.
- `alpine/board/h700/patches/linux/` — H700 kernel patches (panels, GPU, peripherals)
- `alpine/board/rk3326/patches/linux/` — RK3326 kernel patches (panels, input, Wi-Fi)
- `alpine/board/rk3566/patches/linux/` — RK3566 kernel patches (panels, DTS, audio)
- `alpine/board/rk3566/patches/uboot/` — RK3566 U-Boot patches (panel detection, DTB naming)

## U-Boot configs (`uboot.config`)
Source of truth is Alpine tree (`alpine/board/*/uboot.config`). Buildroot references them from there.

## U-Boot env files (`boot.env`)
Per-board boot parameters (`BOOTARGS`, `DEFAULT_DEVICE`, `EXTRA_ENV`). Sourced by `post-build.sh` (Buildroot) and `build.sh` (Alpine) to compile `boot.cmd` → `boot.scr`.
- `alpine/board/h700/boot.env`
- `alpine/board/rk3326/boot.env`
- `alpine/board/rk3566/boot.env`

## Genimage configs
Source of truth is Alpine tree (`alpine/board/`). Buildroot uses the same files passed via `-c`.

## Post-image assembly script (`alpine/board/common/post-image.sh`)
Canonical image packaging pipeline driver shared between Alpine and Buildroot (`buildroot/external/board/common/post-image.sh` is a forwarder wrapper).
Executes stage scripts under `alpine/board/common/post-image.d/`:
- `01-system-erofs.sh` — extracts rootfs tar and generates `system.erofs`.
- `02-initramfs.sh` — stages initramfs dependencies and compiles `initramfs` CPIO archive using `initramfs-init.sh`.
- `03-userdata-vfat.sh` — initializes `device.cfg`, stages DTBs/overlays/UI, and generates `userdata.vfat`.
- `04-genimage.sh` — stages bootloaders, runs `genimage`, and compresses the final image with `xz`.

# Alpine-specific

## World configs (`alpine/configs/`)
Alpine package sets (world-common, world-<board>).

## Validation & probe scripts
- `alpine/board/rk3326/first-boot-probe.sh` — rk3326 initramfs probe.

## Build infrastructure
- `alpine/Makefile` — Alpine build orchestrator
- `alpine/scripts/build.sh` — Alpine image builder (assembles rootfs, installs overlay, runs validation)
- `alpine/container/Dockerfile` — builder container

# Buildroot-specific

## Board-specific Buildroot directories
Per-board extensions under `buildroot/external/board/<board>/`. Invoked by the common `post-build.sh` if present.
- `buildroot/external/board/h700/` — `board.env`
- `buildroot/external/board/rk3326/` — `board.env`, `post-build.sh` (installs USB dongle firmware from Alpine tree)
- `buildroot/external/board/rk3566/` — `board.env`, `post-build.sh` (copies Alpine RK3566 overlay + thermal-watchdog script)

## Defconfigs (`buildroot/external/configs/`)
Buildroot configurations (common.config, <board>.config).

## BusyBox config
`buildroot/external/board/common/busybox.config` — BusyBox applet selection.

## Kernel config fragments (`tiny-*.config`)
Layered kernel configuration fragments merged by `tinykernel/APKBUILD` (Alpine) and referenced by `buildroot/external/configs/*.config` (Buildroot). Order: `tiny-base.config` → `tiny-<board>.config` → `tiny-panfrost.config` → `olddefconfig`.
- `alpine/board/common/tiny-base.config` — base kernel config for all boards
- `alpine/board/common/tiny-panfrost.config` — Panfrost (open-source Mali) fragment
- `alpine/board/common/tiny-libmali.config` — kernel fragment for proprietary libmali
- `alpine/board/h700/tiny-h700.config` — H700 board-specific fragment
- `alpine/board/rk3326/tiny-rk3326.config` — RK3326 board-specific fragment
- `alpine/board/rk3326/tiny-dongles.config` — RK3326 USB dongle Wi-Fi/BT fragment
- `alpine/board/rk3566/tiny-rk3566.config` — RK3566 board-specific fragment

## Build infrastructure
- `buildroot/Makefile` — Buildroot build orchestrator
- `buildroot/external/board/common/post-build.sh` — Buildroot post-build script (copies Alpine OpenRC scripts, shared configs, traits, firmware, device.sh)
- `buildroot/external/board/common/post-image.sh` — Buildroot post-image forwarder wrapper
- `buildroot/external/external.mk`, `external.desc`, `Config.in` — Buildroot external tree hooks
