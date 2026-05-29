# Minime (H700 Custom Linux/Buildroot)

Minimal Buildroot-based custom firmware for Anbernic RG35xxSP and other H700-based handhelds. Uses mainline kernel, libmali drivers. Autoconnects to Wi-Fi using wpa_supplicant and user-provided credentials, enables passwordless telnet and ftp via busybox.

- `Makefile`: VM setup (OrbStack), configs, builds.
- `external/`: Custom Buildroot tree (`BR2_EXTERNAL`).
  - `configs/`: Defconfig files.
  - `board/rg35xxsp/`: SP-specific overlays, DTS, patches, config fragments (`linux.config`/`uboot.config`), and scripts.
  - `package/`: Custom packages (Mali GPU drivers, etc.).
- `buildroot/`: Upstream Buildroot sources.
- `out/`: Target bootable images.
- `logs/`: Build and setup logs.
