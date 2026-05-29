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

## Core Config Files & Unification Symlinks
To simplify maintenance, identical configuration files are shared using symlinks. The **H700 platform acts as the canon platform**, and other platforms symlink to it where possible.

- **BusyBox Configuration**:
  - Canon: [busybox.config](file:///Users/ilembitov/Projects/minime/external/board/h700/busybox.config)
  - Symlinks: RK3326 and RK3566 symlink to H700's version.
- **Rootfs Overlay Folder**:
  - Canon: [h700/overlay/](file:///Users/ilembitov/Projects/minime/external/board/h700/overlay) (contains standard overlays such as `S50telnet`, `S50ftpd`, etc.)
  - Symlinks: RK3326 and RK3566 symlink their `overlay` directories to H700's version.
- **Post-Build Script**:
  - Canon: [post-build.sh](file:///Users/ilembitov/Projects/minime/external/board/h700/post-build.sh)
  - Symlinks: RK3326 and RK3566 symlink to H700's version.
- **Post-Image Script**:
  - Canon: [post-image.sh](file:///Users/ilembitov/Projects/minime/external/board/h700/post-image.sh)
  - Symlinks: RK3326 and RK3566 symlink to H700's version.
- **Genimage Configuration**:
  - Canon (Rockchip): [rk3326/genimage.cfg](file:///Users/ilembitov/Projects/minime/external/board/rk3326/genimage.cfg)
  - Symlinks: RK3566 symlinks to RK3326's version.
  - Device-specific: H700 maintains its own distinct [h700/genimage.cfg](file:///Users/ilembitov/Projects/minime/external/board/h700/genimage.cfg) due to partition table layout differences (MBR vs GPT).
- **U-Boot Boot Script**:
  - Device-specific: [h700/boot.cmd](file:///Users/ilembitov/Projects/minime/external/board/h700/boot.cmd), [rk3326/boot.cmd](file:///Users/ilembitov/Projects/minime/external/board/rk3326/boot.cmd), [rk3566/boot.cmd](file:///Users/ilembitov/Projects/minime/external/board/rk3566/boot.cmd)
- **Kernel Config Fragments**:
  - Canon Base: [tiny-base.config](file:///Users/ilembitov/Projects/minime/external/board/tiny-base.config)
  - Device-specific fragments: [tiny-h700.config](file:///Users/ilembitov/Projects/minime/external/board/h700/tiny-h700.config), [tiny-rk3326.config](file:///Users/ilembitov/Projects/minime/external/board/rk3326/tiny-rk3326.config), [tiny-rk3566.config](file:///Users/ilembitov/Projects/minime/external/board/rk3566/tiny-rk3566.config)
- **Buildroot Defconfigs**:
  - Device-specific: [minime_h700_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_h700_defconfig), [minime_rk3326_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_rk3326_defconfig), [minime_rk3566_defconfig](file:///Users/ilembitov/Projects/minime/external/configs/minime_rk3566_defconfig)


## Agent Directives (Buildroot Quirks & Maintenance)
- **Stale Target Files Cleanup**: Buildroot does not automatically clean up `output/target/` when packages are disabled in the defconfig or when configuration files are modified. Stale target files (like default `S50dropbear` or `S50telnet` scripts) can persist and get packaged into the final filesystem.
  - *Directive*: When modifying defconfigs or packages, the agent must check `output/target/etc/init.d/` and delete any stale files from packages that are no longer enabled. If in doubt, run `make clean` or manually purge the target directory before initiating a build.

