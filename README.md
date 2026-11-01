# Minime

Minimal Alpine Linux OS foundation and frontend for retro gaming handhelds.

## Overview

Minime is a minimal, appliance-like Linux operating system built for retro handheld devices (such as Allwinner H700 and Rockchip RK3566). It boots directly to a lightweight launcher using Alpine Linux (musl libc), Mesa Panfrost GPU acceleration, and DRM/KMS.

## Architecture

* **OS Foundation (`alpine/`)**:
  * Pure Alpine Linux minirootfs with a custom stripped-down mainline kernel (`tinykernel`).
  * Mesa Panfrost OpenGL ES / EGL on direct DRM/KMS.
  * Single FAT32 partition (`.minime/`) with initramfs staging and first-boot partition auto-expansion.
  * Zero-config hardware detection from kernel/device tree traits.
* **CI / Automation (`.github/workflows/`)**:
  * Native arm64 container builder on GitHub Actions.
  * Image creation and packaging (`.img.zst` and update tarball `.tar.zst`).

## Quick Start

```sh
# Run fast static checks and package verification
task validate

# Build flashable SD card image (defaults to BOARD=h700)
task build

# Build for a specific target board (h700 | rk3566)
task build BOARD=rk3566

# Clean build outputs
task clean
```
