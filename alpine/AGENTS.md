# Minime (Custom Linux/Buildroot firmware)

Minimal Buildroot-based custom firmware for Anbernic handhelds based on RK3326, H700 and RK3566 SoCs. Currently only tested on Anbernic RG35xxSP v1.

Uses mainline kernel, libmali drivers. Autoconnects to Wi-Fi using wpa_supplicant and user-provided credentials, enables passwordless telnet and ftp via busybox.

- `Makefile`: VM setup (OrbStack), configs, builds.
- `external/`: Custom Buildroot tree (`BR2_EXTERNAL`).
  - `configs/`: Defconfig files.
  - `board/h700/`: H700-specific overlays, DTS, patches, config fragments (`linux.config`/`uboot.config`), and scripts.
  - `package/`: Custom packages (Mali GPU drivers, etc.).
- `buildroot/`: Upstream Buildroot sources.
- `out/`: Target bootable images.
- `logs/`: Build and setup logs.

## Core Config Files
- H700 Canon Defconfig: [minime_h700_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_h700_defconfig)
- RK3326 Defconfig: [minime_rk3326_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_rk3326_defconfig)
- RK3566 Defconfig: [minime_rk3566_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_rk3566_defconfig)
- Canon BusyBox Config: [busybox.config](file:///Users/ilembitov/Projects/minime/external/board/h700/busybox.config)
- Base Kernel Config Fragment: [tiny-base.config](file:///Users/ilembitov/Projects/minime/external/board/tiny-base.config)
- Board-Specific Kernel Config Fragments:
  - H700: [tiny-h700.config](file:///Users/ilembitov/Projects/minime/external/board/h700/tiny-h700.config)
  - RK3326: [tiny-rk3326.config](file:///Users/ilembitov/Projects/minime/external/board/rk3326/tiny-rk3326.config)
  - RK3566: [tiny-rk3566.config](file:///Users/ilembitov/Projects/minime/external/board/rk3566/tiny-rk3566.config)
- Canon Scripts:
  - Post-Build: [post-build.sh](file:///Users/ilembitov/Projects/minime/external/board/h700/post-build.sh)
  - Post-Image: [post-image.sh](file:///Users/ilembitov/Projects/minime/external/board/h700/post-image.sh)

## Agent Directives (Buildroot Quirks & Maintenance)
- **Stale Target Files Cleanup**: Buildroot does not automatically clean up `output/target/` when packages are disabled in the defconfig or when configuration files are modified. Stale target files (like default `S50dropbear` or `S50telnet` scripts) can persist and get packaged into the final filesystem.
  - *Directive*: When modifying defconfigs or packages, the agent must check `output/target/etc/init.d/` and delete any stale files from packages that are no longer enabled. If in doubt, run `make clean` or manually purge the target directory before initiating a build.

