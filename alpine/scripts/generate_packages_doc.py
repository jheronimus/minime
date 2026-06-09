#!/usr/bin/env python3
import os
import subprocess
import sys

# Dictionary of package descriptions for target packages and host tools
PACKAGE_DESCRIPTIONS = {
    # Custom packages
    "minui": "Minimal launcher frontend and UI shell for the system",
    "panfrost": "Mesa3D Panfrost driver configuration and wrapper package (H700)",
    "libmali": "Proprietary ARM Mali user-space GPU library binaries (Rockchip)",
    "mali-kbase": "Proprietary ARM Mali GPU kernel driver module (Rockchip)",
    "drkhrse_miyoo_bezels": "Custom screen bezels for Miyoo Mini emulator scaling",
    "preloaded-roms": "Collection of preloaded open-source ROMs and homebrew",
    "retroarch-cores": "Build recipe for libretro emulation cores",
    "retroarch-frontend": "RetroArch emulator frontend package",
    
    # Audio/Bluetooth
    "alsa-lib": "Advanced Linux Sound Architecture interface library",
    "bluez-alsa": "Bluetooth Audio ALSA backend (ALSA proxy for A2DP)",
    "bluez5_utils": "Official Linux Bluetooth protocol stack utilities",
    "sbc": "Subband Codec library for Bluetooth audio streaming",
    
    # System core & Init
    "busybox": "Swiss army knife of embedded Linux (basic shell utilities)",
    "dbus": "Message bus system for inter-process communication (IPC)",
    "eudev": "Device file manager (kernel event listener), fork of udev",
    "udev": "Virtual package provider for device management",
    "initscripts": "System initialization and startup scripts",
    "ifupdown-scripts": "Scripts to configure network interfaces on boot",
    "urandom-scripts": "Scripts to seed the random number generator at boot",
    "skeleton": "Directory structure skeleton for the root filesystem",
    "skeleton-init-common": "Common files for system initialization",
    "skeleton-init-sysv": "System V style initialization structure",
    
    # Graphics & Input libraries
    "libdrm": "Direct Rendering Manager userspace library",
    "libedit": "Command line editing and history library (BSD alternative to GNU readline)",
    "libegl": "EGL API interface for binding OpenGL/GLES to display window system",
    "libgbm": "Generic Buffer Management library for memory allocation",
    "libgles": "OpenGL for Embedded Systems (GLES) API library",
    "mesa3d-headers": "Mesa3D graphics library development headers",
    "sdl2": "Simple DirectMedia Layer 2 (cross-platform media and input library)",
    "sdl2_image": "SDL2 image loading library (handles PNG, BMP, JPG, etc.)",
    "sdl2_ttf": "SDL2 TrueType Font rendering library",
    "freetype": "Software library to render fonts",
    
    # Libraries & Dependencies
    "expat": "Stream-oriented XML parser library in C",
    "libffi": "Foreign Function Interface library",
    "libglib2": "Core application building block library from GNOME",
    "libnl": "Netlink Protocol Library to communicate with kernel netlink sockets",
    "libpng": "Official PNG reference library (used on H700 for external png loading)",
    "libpthread-stubs": "Weak aliases for pthread functions (stubs for platforms without threads)",
    "libxml2": "XML parsing library",
    "libzlib": "Virtual package mapping to the zlib compression library",
    "lz4": "Extremely fast compression algorithm library",
    "ncurses": "Text-based user interface rendering library",
    "pcre2": "Perl-compatible Regular Expressions library",
    "readline": "GNU library for command-line editing and history",
    "zlib": "Compression library using the DEFLATE algorithm",
    "zstd": "Zstandard fast real-time compression algorithm library",
    
    # Kernel & Bootloaders
    "linux": "Mainline Linux kernel",
    "uboot": "Universal Boot Loader (U-Boot)",
    "arm-trusted-firmware": "Secure world ARM Trusted Firmware (ATF/TF-A)",
    "rockchip-rkbin": "Rockchip firmware binaries (TPL/DDR initialization blobs)",
    
    # Toolchain
    "toolchain": "Buildroot toolchain wrapper package",
    "toolchain-external": "External toolchain integration wrapper",
    "toolchain-external-arm-aarch64": "Arm GNU Toolchain for AArch64 Cortex-A processors",
    
    # Utilities
    "dosfstools": "Utilities to create and check FAT filesystems (mkfs.vfat)",
    "kmod": "Utilities for loading, unloading, and querying kernel modules",
    "mdnsd": "Minimal RFC-compliant Multicast DNS (mDNS) daemon",
    "util-linux": "Standard system utilities (mount, partx, fdisk, etc.)",
    "util-linux-libs": "Shared utility libraries from util-linux",
    "wireless-regdb": "Wireless regulatory database for Wi-Fi compliance",
    "wpa_supplicant": "Wi-Fi networking client daemon with WPA/WPA2/WPA3 support",
    "rootfs-tar": "Buildroot recipe to pack the target directory into a tarball",
    
    # Host tools
    "host-acl": "Host Access Control List utilities",
    "host-attr": "Host filesystem extended attributes utilities",
    "host-autoconf": "Host automatic configure script generator",
    "host-automake": "Host automatic Makefile generator",
    "host-blake3": "Host BLAKE3 cryptographic hash tool",
    "host-ccache": "Host compiler cache for faster compilation",
    "host-dtc": "Host Device Tree Compiler (dtc) for compiling DTS to DTB",
    "host-eudev": "Host udev administration tools",
    "host-fakeroot": "Host fakeroot utility to run commands in a simulated root environment",
    "host-hiredis": "Host Redis client library",
    "host-kmod": "Host kmod tools for kernel module compilation helper",
    "host-libtool": "Host generic library support script",
    "host-libxcrypt": "Host cryptographic library for password hashing",
    "host-m4": "Host macro processor",
    "host-makedevs": "Host utility to create device files based on a table",
    "host-mkpasswd": "Host utility to generate encrypted passwords",
    "host-patchelf": "Host utility to modify ELF binaries' RPATH and interpreter",
    "host-pkgconf": "Host compiler package configuration helper",
    "host-skeleton": "Host filesystem structure skeleton",
    "host-xxhash": "Host xxHash fast non-cryptographic checksum utility",
    "host-zstd": "Host Zstandard compression utility"
}

BOARDS = ["h700", "rk3326", "rk3566"]

def run_make(board, target):
    """Runs a make target for the specified board and returns output."""
    cmd = ["make", f"BOARD={board}", target]
    print(f"Running: {' '.join(cmd)} ...", file=sys.stderr)
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    if result.returncode != 0:
        print(f"Error running make for board {board}, target {target}:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)
    return result.stdout

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    minime_dir = os.path.dirname(script_dir)
    docs_dir = os.path.abspath(os.path.join(minime_dir, "..", "docs"))
    packages_md = os.path.join(docs_dir, "PACKAGES.md")
    
    # Ensure docs directory exists
    os.makedirs(docs_dir, exist_ok=True)
    
    # Change cwd to minime directory where the Makefile is
    os.chdir(minime_dir)
    
    # Gather targets for each board
    board_targets = {}
    all_packages = set()
    
    for board in BOARDS:
        # First ensure defconfig is applied
        run_make(board, "defconfig")
        # Get target list
        output = run_make(board, "show-targets")
        
        # Clean up output
        targets = []
        for line in output.splitlines():
            # Skip any logs or enter/leave directory messages
            if "make:" in line or "LOG=" in line or not line.strip():
                continue
            targets.extend(line.strip().split())
            
        board_targets[board] = set(targets)
        all_packages.update(targets)
        
    # Categorize packages into target and host
    sorted_packages = sorted(list(all_packages))
    target_pkgs = [p for p in sorted_packages if not p.startswith("host-")]
    host_pkgs = [p for p in sorted_packages if p.startswith("host-")]
    
    # Generate MD Content
    md = []
    md.append("# Minime OS Package Inventory")
    md.append("")
    md.append("This document tracks the full list of all target and host packages Buildroot is configured to build for Minime OS images. This inventory is automatically kept up-to-date by running the documentation generation script.")
    md.append("")
    md.append("> [!NOTE]")
    md.append("> This list was generated automatically. To update it, run: `make packages-list` in the `minime/` directory.")
    md.append("")
    md.append("## Target Packages")
    md.append("")
    md.append("These packages are compiled for the target device's filesystem or represent hardware-specific system files (such as kernels and bootloaders).")
    md.append("")
    md.append("| Package | H700 | RK3326 | RK3566 | Description / Purpose |")
    md.append("| :--- | :---: | :---: | :---: | :--- |")
    
    for pkg in target_pkgs:
        h700_tick = "✓" if pkg in board_targets["h700"] else ""
        rk3326_tick = "✓" if pkg in board_targets["rk3326"] else ""
        rk3566_tick = "✓" if pkg in board_targets["rk3566"] else ""
        desc = PACKAGE_DESCRIPTIONS.get(pkg, "*No description provided*")
        md.append(f"| `{pkg}` | {h700_tick} | {rk3326_tick} | {rk3566_tick} | {desc} |")
        
    md.append("")
    md.append("## Host Build Tools (`host-*`)")
    md.append("")
    md.append("These packages are compiled for the host development system (build machine) to assist in compiling, linking, formatting, or packaging the target system.")
    md.append("")
    md.append("| Host Package | H700 | RK3326 | RK3566 | Description / Purpose |")
    md.append("| :--- | :---: | :---: | :---: | :--- |")
    
    for pkg in host_pkgs:
        h700_tick = "✓" if pkg in board_targets["h700"] else ""
        rk3326_tick = "✓" if pkg in board_targets["rk3326"] else ""
        rk3566_tick = "✓" if pkg in board_targets["rk3566"] else ""
        desc = PACKAGE_DESCRIPTIONS.get(pkg, "*No description provided*")
        md.append(f"| `{pkg}` | {h700_tick} | {rk3326_tick} | {rk3566_tick} | {desc} |")
        
    md.append("")
    md.append("## Key Package Differences")
    md.append("")
    md.append("### 1. GPU Driver Stack & Libraries")
    md.append("- **H700**: Uses the open-source **`panfrost`** GPU driver stack combined with **`mesa3d-headers`**.")
    md.append("- **RK3326 & RK3566**: Rely on the proprietary ARM Mali user-space library (**`libmali`**) and its corresponding proprietary kernel module (**`mali-kbase`**).")
    md.append("")
    md.append("### 2. Bootloader and ATF Blobs")
    md.append("- **H700 & RK3326**: Build the secure-world firmware (**`arm-trusted-firmware`**) from source repository.")
    md.append("- **RK3566**: Uses Rockchip's pre-compiled binary initialization files provided by **`rockchip-rkbin`** instead of compilation from source.")
    md.append("")
    md.append("### 3. Optional Feature Libraries (e.g., `libpng`)")
    md.append("- **Why is `libpng` only built for H700?**")
    md.append("  `sdl2_image` has optional support for PNG image decoding via `libpng`. If `BR2_PACKAGE_LIBPNG` is not enabled, `sdl2_image` falls back to its internal, lightweight **`stb_image`** decoder. ")
    md.append("  On RK3326 and RK3566, `libpng` is omitted, and the system relies on this lightweight `stb_image` integration. H700 explicitly sets `BR2_PACKAGE_LIBPNG=y` in its defconfig, prompting `sdl2_image` to build with `--enable-png` and link against the external `libpng` library.")
    md.append("")
    
    with open(packages_md, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
        
    print(f"Successfully generated {packages_md}!", file=sys.stderr)

if __name__ == "__main__":
    main()
