# Minime OS Package Inventory

This document tracks the full list of all target and host packages Buildroot is configured to build for Minime OS images. This inventory is automatically kept up-to-date by running the documentation generation script.

> [!NOTE]
> This list was generated automatically. To update it, run: `make packages-list` in the `minime/` directory.

## Target Packages

These packages are compiled for the target device's filesystem or represent hardware-specific system files (such as kernels and bootloaders).

| Package | H700 | RK3326 | RK3566 | Description / Purpose |
| :--- | :---: | :---: | :---: | :--- |
| `allium` |  |  | ✓ | *No description provided* |
| `allium-themes` |  |  | ✓ | *No description provided* |
| `alsa-lib` | ✓ | ✓ | ✓ | Advanced Linux Sound Architecture interface library |
| `alsa-utils` | ✓ | ✓ | ✓ | *No description provided* |
| `arm-trusted-firmware` | ✓ | ✓ |  | Secure world ARM Trusted Firmware (ATF/TF-A) |
| `bluez-alsa` | ✓ | ✓ | ✓ | Bluetooth Audio ALSA backend (ALSA proxy for A2DP) |
| `bluez5_utils` | ✓ | ✓ | ✓ | Official Linux Bluetooth protocol stack utilities |
| `busybox` | ✓ | ✓ | ✓ | Swiss army knife of embedded Linux (basic shell utilities) |
| `dbus` | ✓ | ✓ | ✓ | Message bus system for inter-process communication (IPC) |
| `dosfstools` | ✓ | ✓ | ✓ | Utilities to create and check FAT filesystems (mkfs.vfat) |
| `drkhrse_miyoo_bezels` | ✓ | ✓ | ✓ | Custom screen bezels for Miyoo Mini emulator scaling |
| `dufs` |  |  | ✓ | *No description provided* |
| `eudev` | ✓ | ✓ | ✓ | Device file manager (kernel event listener), fork of udev |
| `expat` | ✓ | ✓ | ✓ | Stream-oriented XML parser library in C |
| `fatresize` | ✓ | ✓ | ✓ | *No description provided* |
| `freetype` | ✓ | ✓ | ✓ | Software library to render fonts |
| `ifupdown-scripts` | ✓ | ✓ | ✓ | Scripts to configure network interfaces on boot |
| `initscripts` | ✓ | ✓ | ✓ | System initialization and startup scripts |
| `kmod` | ✓ | ✓ | ✓ | Utilities for loading, unloading, and querying kernel modules |
| `libdrm` | ✓ | ✓ | ✓ | Direct Rendering Manager userspace library |
| `libedit` | ✓ | ✓ | ✓ | Command line editing and history library (BSD alternative to GNU readline) |
| `libegl` | ✓ | ✓ | ✓ | EGL API interface for binding OpenGL/GLES to display window system |
| `libffi` | ✓ | ✓ | ✓ | Foreign Function Interface library |
| `libgbm` | ✓ | ✓ | ✓ | Generic Buffer Management library for memory allocation |
| `libgles` | ✓ | ✓ | ✓ | OpenGL for Embedded Systems (GLES) API library |
| `libglib2` | ✓ | ✓ | ✓ | Core application building block library from GNOME |
| `libmali` | ✓ | ✓ | ✓ | Proprietary ARM Mali user-space GPU library binaries (Rockchip) |
| `libnl` | ✓ | ✓ | ✓ | Netlink Protocol Library to communicate with kernel netlink sockets |
| `libpng` | ✓ | ✓ | ✓ | Official PNG reference library (used on H700 for external png loading) |
| `libpthread-stubs` | ✓ | ✓ | ✓ | Weak aliases for pthread functions (stubs for platforms without threads) |
| `libretro-common` | ✓ | ✓ | ✓ | *No description provided* |
| `libxml2` | ✓ | ✓ | ✓ | XML parsing library |
| `libzlib` | ✓ | ✓ | ✓ | Virtual package mapping to the zlib compression library |
| `linux` | ✓ | ✓ | ✓ | Mainline Linux kernel |
| `lz4` | ✓ | ✓ |  | Extremely fast compression algorithm library |
| `mali-kbase` | ✓ | ✓ | ✓ | Proprietary ARM Mali GPU kernel driver module (Rockchip) |
| `mdnsd` | ✓ | ✓ | ✓ | Minimal RFC-compliant Multicast DNS (mDNS) daemon |
| `minui` | ✓ | ✓ |  | Minimal launcher frontend and UI shell for the system |
| `ncurses` | ✓ | ✓ | ✓ | Text-based user interface rendering library |
| `parted` | ✓ | ✓ | ✓ | *No description provided* |
| `pcre2` | ✓ | ✓ | ✓ | Perl-compatible Regular Expressions library |
| `readline` | ✓ | ✓ | ✓ | GNU library for command-line editing and history |
| `retroarch-cores` | ✓ | ✓ | ✓ | Build recipe for libretro emulation cores |
| `rockchip-rkbin` |  |  | ✓ | Rockchip firmware binaries (TPL/DDR initialization blobs) |
| `rootfs-tar` | ✓ | ✓ | ✓ | Buildroot recipe to pack the target directory into a tarball |
| `sbc` | ✓ | ✓ | ✓ | Subband Codec library for Bluetooth audio streaming |
| `sdl2` | ✓ | ✓ | ✓ | Simple DirectMedia Layer 2 (cross-platform media and input library) |
| `sdl2_image` | ✓ | ✓ | ✓ | SDL2 image loading library (handles PNG, BMP, JPG, etc.) |
| `sdl2_ttf` | ✓ | ✓ | ✓ | SDL2 TrueType Font rendering library |
| `skeleton` | ✓ | ✓ | ✓ | Directory structure skeleton for the root filesystem |
| `skeleton-init-common` | ✓ | ✓ | ✓ | Common files for system initialization |
| `skeleton-init-sysv` | ✓ | ✓ | ✓ | System V style initialization structure |
| `syncthing` |  |  | ✓ | *No description provided* |
| `toolchain` | ✓ | ✓ | ✓ | Buildroot toolchain wrapper package |
| `toolchain-external` | ✓ | ✓ | ✓ | External toolchain integration wrapper |
| `toolchain-external-arm-aarch64` | ✓ | ✓ | ✓ | Arm GNU Toolchain for AArch64 Cortex-A processors |
| `uboot` | ✓ | ✓ | ✓ | Universal Boot Loader (U-Boot) |
| `udev` | ✓ | ✓ | ✓ | Virtual package provider for device management |
| `urandom-scripts` | ✓ | ✓ | ✓ | Scripts to seed the random number generator at boot |
| `util-linux` | ✓ | ✓ | ✓ | Standard system utilities (mount, partx, fdisk, etc.) |
| `util-linux-libs` | ✓ | ✓ | ✓ | Shared utility libraries from util-linux |
| `wireless-regdb` | ✓ | ✓ | ✓ | Wireless regulatory database for Wi-Fi compliance |
| `wpa_supplicant` | ✓ | ✓ | ✓ | Wi-Fi networking client daemon with WPA/WPA2/WPA3 support |
| `zlib` | ✓ | ✓ | ✓ | Compression library using the DEFLATE algorithm |
| `zstd` | ✓ | ✓ | ✓ | Zstandard fast real-time compression algorithm library |

## Host Build Tools (`host-*`)

These packages are compiled for the host development system (build machine) to assist in compiling, linking, formatting, or packaging the target system.

| Host Package | H700 | RK3326 | RK3566 | Description / Purpose |
| :--- | :---: | :---: | :---: | :--- |
| `host-acl` | ✓ | ✓ | ✓ | Host Access Control List utilities |
| `host-attr` | ✓ | ✓ | ✓ | Host filesystem extended attributes utilities |
| `host-autoconf` | ✓ | ✓ | ✓ | Host automatic configure script generator |
| `host-automake` | ✓ | ✓ | ✓ | Host automatic Makefile generator |
| `host-blake3` | ✓ | ✓ | ✓ | Host BLAKE3 cryptographic hash tool |
| `host-ccache` | ✓ | ✓ | ✓ | Host compiler cache for faster compilation |
| `host-dtc` | ✓ | ✓ | ✓ | Host Device Tree Compiler (dtc) for compiling DTS to DTB |
| `host-eudev` | ✓ | ✓ | ✓ | Host udev administration tools |
| `host-fakeroot` | ✓ | ✓ | ✓ | Host fakeroot utility to run commands in a simulated root environment |
| `host-go-bin` |  |  | ✓ | *No description provided* |
| `host-hiredis` | ✓ | ✓ | ✓ | Host Redis client library |
| `host-kmod` | ✓ | ✓ | ✓ | Host kmod tools for kernel module compilation helper |
| `host-libtool` | ✓ | ✓ | ✓ | Host generic library support script |
| `host-libxcrypt` | ✓ | ✓ | ✓ | Host cryptographic library for password hashing |
| `host-m4` | ✓ | ✓ | ✓ | Host macro processor |
| `host-makedevs` | ✓ | ✓ | ✓ | Host utility to create device files based on a table |
| `host-mkpasswd` | ✓ | ✓ | ✓ | Host utility to generate encrypted passwords |
| `host-patchelf` | ✓ | ✓ | ✓ | Host utility to modify ELF binaries' RPATH and interpreter |
| `host-pkgconf` | ✓ | ✓ | ✓ | Host compiler package configuration helper |
| `host-rust-bin` |  |  | ✓ | *No description provided* |
| `host-skeleton` | ✓ | ✓ | ✓ | Host filesystem structure skeleton |
| `host-xxhash` | ✓ | ✓ | ✓ | Host xxHash fast non-cryptographic checksum utility |
| `host-zstd` | ✓ | ✓ | ✓ | Host Zstandard compression utility |

## Key Package Differences

### 1. GPU Driver Stack & Libraries
- **H700**: Uses the open-source **`panfrost`** GPU driver stack combined with **`mesa3d-headers`**.
- **RK3326 & RK3566**: Rely on the proprietary ARM Mali user-space library (**`libmali`**) and its corresponding proprietary kernel module (**`mali-kbase`**).

### 2. Bootloader and ATF Blobs
- **H700 & RK3326**: Build the secure-world firmware (**`arm-trusted-firmware`**) from source repository.
- **RK3566**: Uses Rockchip's pre-compiled binary initialization files provided by **`rockchip-rkbin`** instead of compilation from source.

### 3. Optional Feature Libraries (e.g., `libpng`)
- **Why is `libpng` only built for H700?**
  `sdl2_image` has optional support for PNG image decoding via `libpng`. If `BR2_PACKAGE_LIBPNG` is not enabled, `sdl2_image` falls back to its internal, lightweight **`stb_image`** decoder. 
  On RK3326 and RK3566, `libpng` is omitted, and the system relies on this lightweight `stb_image` integration. H700 explicitly sets `BR2_PACKAGE_LIBPNG=y` in its defconfig, prompting `sdl2_image` to build with `--enable-png` and link against the external `libpng` library.

