# MAP: Alpine-only

Genuinely Alpine-exclusive files. Syntax/init system/packaging differ
fundamentally from Buildroot. Not merge candidates.

## Init scripts (OpenRC)

All under `alpine/aports/minime-overlay/files/etc/init.d/`. OpenRC syntax
(`depend()`, `start()`, `stop()`, runlevels). Cannot share with Buildroot's
Busybox init (bare sh + rcS).

| Script | Service |
|---|---|
| `minime-modules` | Kernel module loading |
| `minime-wifi` | wpa_supplicant + udhcpc Wi-Fi |
| `minime-ftpd` | Anonymous FTP (tcpsvd) |
| `minime-telnetd` | Passwordless telnet (utelnetd) |
| `minime-bluetooth` | On-demand bluetoothd |
| `minime-dbus` | On-demand D-Bus |
| `minime-bluealsa` | BlueALSA A2DP |
| `minime-panfrost` | Panfrost GPU module loader |
| `minime-bootsplash` | Animated boot splash |
| `minime-traits` | Device traits generation |
| `minime-fb-unblank` | Framebuffer unblank |
| `minime-ui` | Frontend launcher |

## Overlay configs

All under `alpine/aports/minime-overlay/files/`.

| Path | Purpose |
|---|---|
| `etc/hosts` | Static hosts (localhost + minime) |
| `etc/hostname` | Hostname = minime |
| `etc/fstab` | Synthetic mounts only (proc, sysfs, devpts, tmpfs) |
| `etc/profile.d/minime.sh` | SD card path env vars for login shells |
| `etc/modprobe.d/rtw88.conf` | Disable Wi-Fi LPS deep sleep |
| `etc/modules-load.d/wifi.conf` | Auto-load cfg80211, mac80211, rtw88* |
| `etc/udev/rules.d/50-panfrost.rules` | DRM/Panfrost permissions (group video) |
| `usr/share/minime/scripts/minime-ui` | UI launcher with SD card path exports |
| `usr/share/minime/scripts/minime-wifi` | Wi-Fi connection state machine |

The `minime-ui` and `minime-wifi` scripts are Alpine's runtime helpers.
Buildroot embeds equivalent logic inline in its S## init scripts.

## Kernel config fragments (`alpine/board/`)

| Fragment | Scope |
|---|---|
| `common/tiny-base.config` | Base: CONFIG_BLK_DEV, filesystems, net, input, sound |
| `common/tiny-panfrost.config` | Panfrost GPU (Mesa userspace) |
| `h700/tiny-h700.config` | H700: SUNXI, RTW88, BT, PWM |
| `rk3326/tiny-rk3326.config` | RK3326: ROCKCHIP, DRM, WiFi |
| `rk3326/tiny-dongles.config` | USB dongle Wi-Fi/BT drivers |
| `rk3566/tiny-rk3566.config` | RK3566: SCMI, DDR devfreq, Mali-Bifrost |

Buildroot embeds equivalent options in `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_PATHS`.
The fragment mechanism differs per build system.

## World configs (`alpine/configs/`)

| File | Purpose |
|---|---|
| `world-common` | Shared package set for all boards |
| `world-h700` | H700-specific packages |
| `world-rk3326` | RK3326-specific packages |
| `world-rk3566` | RK3566-specific packages |

Alpine's equivalent of Buildroot defconfigs. Different package manager
and syntax (`apk` world files vs `BR2_PACKAGE_*`).

## Build infrastructure

| Path | Purpose |
|---|---|
| `Makefile` | Build orchestration (image, shell, prepare, clean) |
| `scripts/build.sh` | Full Alpine image builder (415 lines) |
| `container/Dockerfile` | Builder container definition |
| `container/minime-builder.rsa` | APK signing key (private) |
| `container/minime-builder.rsa.pub` | APK signing key (public) |

No Buildroot equivalents. Buildroot uses its own `Makefile` + CI workflows.
