# ADR 0001: Dual-Distro Architecture & Path Resolution Contract

## Status

Accepted

## Context

Minime is designed to provide two distinct, bootable firmware flavors:
1. **Alpine Linux**: A fast-building, lightweight musl-libc based firmware.
2. **Buildroot**: A glibc-based firmware intended for broad compatibility with closed-source blobs (e.g., proprietary Mali drivers, Drastic, Pico-8).

Maintaining two parallel distributions traditionally introduces overhead, especially when providing Over-The-Air (OTA) updates or simple update mechanisms for end-users. We needed a reliable strategy that allows users to:
1. Update their firmware without having to re-flash the entire SD card using tools like balenaEtcher or Rufus.
2. Preserve their user data (ROMs, BIOS files, saves) seamlessly during an update.
3. Switch effortlessly between the Alpine and Buildroot firmwares on the same hardware without risking bootloader corruption or requiring a full wipe.

## Decision

We will enforce a unified `genimage` architecture and a shared boot payload structure for both Alpine and Buildroot targets. 

1. **Shared Partition Layout**: Both distributions share the exact same `genimage.cfg` layouts (`packages/components/boards/common/genimage.cfg`, with per-board overrides for h700 and rk3326). The SD card layout consists solely of raw, out-of-partition U-Boot bootloader blobs (placed at precise offsets depending on the chipset) and a single, first-boot expandable FAT32 partition.
2. **Unified Build Pipeline**: Both Alpine and Buildroot share the same image packaging scripts in `packages/image/`, invoked via the shared packager container.
3. **File-Based OS Payload**: The entire OS is encapsulated into portable files located at the root of the FAT32 partition:
   - `system.erofs`: The immutable, compressed root filesystem.
   - `boot/`: A directory containing the kernel (`Image`), device trees (`.dtb`), and the initramfs (`initramfs.cpio.gz`).

## Path Architecture Contract

To ensure dual-distro co-equality and prevent path drift across Alpine and Buildroot target builders:

1. **`MINIME_ROOT`**: Absolute path to the monorepo root directory (`/workspace` inside container, or repository root on host). All shared assets (`boards/`, `uboot/`, `genimage/`, `src/`, `roms/`) resolve relative to `MINIME_ROOT`.
2. **Target Roots (`ALPINE_ROOT` / `BUILDROOT_ROOT`)**: Absolute path to the target distro directory (`${MINIME_ROOT}/packages/components/alpine` and `${MINIME_ROOT}/packages/components/buildroot`). Target-local assets (`aports/`, `external/`, `configs/`, target scripts) resolve relative to their target root.

## Consequences

* **Trivial Drag-and-Drop Updates**: Because the active OS resides entirely inside standard files on a universally readable FAT32 partition, users can update their firmware by simply plugging their SD card into any PC (Windows, macOS, Linux) and overwriting `system.erofs` and the `boot/` folder.
* **On-Device Updates**: Implementing an on-device OTA updater becomes extremely simple. A script only needs to download a `.zip` payload containing the new kernel/erofs, extract it directly over `/mnt/sdcard/`, and reboot the system.
* **Seamless Distro Switching**: A user running the Alpine build can swap to the Buildroot build (or vice versa) simply by replacing the OS payload files on the FAT32 partition. The underlying U-Boot bootloader blobs outside the partition table do not need to be touched or flashed.
* **Guaranteed Data Preservation**: Since the update process is restricted to overwriting the specific system files, all user configurations, ROMs, and saves existing on the single FAT32 partition remain completely undisturbed.
* **Deterministic Path Resolution**: Resolving shared assets relative to `MINIME_ROOT` and target assets relative to `ALPINE_ROOT`/`BUILDROOT_ROOT` eliminates fragile relative depth ascents (`../../../`), hardcoded container assumptions, and path string replacements.
