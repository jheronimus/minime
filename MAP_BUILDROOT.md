# MAP: Buildroot-only

Genuinely Buildroot-exclusive files. Syntax/init system/packaging differ
fundamentally from Alpine. Not merge candidates.

## Init scripts (Busybox S##)

All under `buildroot/external/board/common/overlay/etc/init.d/`. Bare sh
with `start()/stop()/status()` sourced by `rcS`. Same services as Alpine's
OpenRC scripts, but syntax is different.

| Script | Service | Alpine equivalent |
|---|---|---|
| `S05modules` | Kernel module loading | `minime-modules` |
| `S05unblank` | FB unblank | `minime-fb-unblank` |
| `S09detect-traits` | Device traits detection | `minime-traits` |
| `S10gpudriver` | Mali GPU driver init | `minime-panfrost` |
| `S30dbus-daemon` | D-Bus daemon | `minime-dbus` |
| `S40bluetoothd` | Bluetooth daemon | `minime-bluetooth` |
| `S41bluealsa` | BlueALSA | `minime-bluealsa` |
| `S45wifi` | Wi-Fi management | `minime-wifi` |
| `S50ftpd` | FTP daemon | `minime-ftpd` |
| `S50telnet` | Telnet daemon | `minime-telnetd` |
| `S55bootsplash` | Boot splash | `minime-bootsplash` |
| `S60ui` | Frontend launcher | `minime-ui` |

### RK3566-only

| Path | Service |
|---|---|
| `board/rk3566/overlay/etc/init.d/S15thermal-watchdog` | Thermal watchdog daemon |

No Alpine equivalent. RK3566-specific userspace thermal management.

## Overlay configs

All under `buildroot/external/board/common/overlay/`.

| Path | Purpose | Alpine equivalent |
|---|---|---|
| `etc/inittab` | Busybox init (no getty on tty1) | OpenRC default |
| `etc/fstab` | Mounts (erofs root + synthetic) | Different (no root mount) |
| `etc/default/seedrng` | Random seed on SD card | None |
| `etc/sysctl.d/00-minime.conf` | Sysctl tuning (TCP, panic, dirty_ratio, etc.) | None (inherits Alpine defaults) |
| `etc/udev/rules.d/50-mali.rules` | Mali GPU permissions (mali0) | `50-panfrost.rules` (different GPU) |

## Board env

`board/{h700,rk3326,rk3566}/board.env` — shell-sourced variables
identifying DTB patterns, image names, and autodetection support.
Alpine derives equivalent info from board directory structure.

## Defconfigs (`buildroot/external/configs/`)

| File | Purpose |
|---|---|
| `minime_common.config` | Shared BR2 options (arch, toolchain, packages) |
| `minime_h700.config` | H700 full defconfig |
| `minime_rk3326.config` | RK3326 full defconfig |
| `minime_rk3566.config` | RK3566 full defconfig |
| `bootloader/bootloader-h700.config` | H700 U-Boot-only defconfig (CI) |
| `bootloader/bootloader-rk3326.config` | RK3326 U-Boot/ATF defconfig (CI) |
| `bootloader/bootloader-rk3566.config` | RK3566 U-Boot/ATF defconfig (CI) |

## BusyBox config

`board/common/busybox.config` — BusyBox applet selection.
Alpine uses BusyBox from Alpine packages; no equivalent.

## GPU kernel fragment

`board/common/tiny-libmali.config` — Mali kernel config for proprietary
libmali userspace. Alpine uses `tiny-panfrost.config` instead.

## Validation scripts

| Path | Purpose |
|---|---|
| `board/common/check-traits.sh` | Traits completeness/validity checker |
| `board/rk3326/first-boot-probe.sh` | RK3326 hardware autodetection (initramfs) |

## Build infrastructure

| Path | Purpose |
|---|---|
| `buildroot/Makefile` | Build orchestration |
| `board/common/post-build.sh` | Common post-build (boot.scr, firmware, traits, udev) |
| `board/common/post-image.sh` | Image assembly |
| `external.mk` | BR2_EXTERNAL make includes |
| `external.desc` | BR2_EXTERNAL description |
| `Config.in` | External tree Kconfig root |
