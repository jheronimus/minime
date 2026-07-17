# Linux Kernel Patches for RK3326 Handhelds

These patches are applied to the mainline Linux kernel (`7.0.10`) during the Buildroot compilation process.

## Source Reference
The hardware and board support patches were imported from the **[ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)** project:
- **Repository URL**: `https://github.com/ROCKNIX/distribution`
- **Imported Commit**: `61f7ff705bc3515f91757876a6cf9bdf483789ea`
- **Description**: Mainline kernel display/backlight/PHY/DTS patches for Anbernic RK3326-based devices.

## Active Patches
All imported patches are applied exactly as they are configured in Rocknix's RK3326 build, enabling standard screen panel timings, unique GPIO guidelines, Realtek SDIO Wi-Fi, and standard USB configurations for Anbernic RG351 devices.
