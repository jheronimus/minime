# Linux Kernel Patches for RK3566 Handhelds

These patches are applied to the mainline Linux kernel (`7.0.10`) during the Buildroot compilation process.

## Source Reference
The hardware and board support patches were imported from the **[ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)** project:
- **Repository URL**: `https://github.com/ROCKNIX/distribution`
- **Imported Commit**: `61f7ff705bc3515f91757876a6cf9bdf483789ea`
- **Description**: Mainline kernel display/backlight/PHY/DTS patches for Anbernic RK3566-based devices.

## Omitted Patches
To ensure a mainline-clean and highly optimized system, we have omitted several patches that are specific only to Powkiddy or non-Anbernic devices:
* **`0009-arm64-dts-rockchip-fix-shoulders-triggers-on-powkidd.patch`**: Powkiddy-specific hardware button fixes.
* **`0010-drm-panel-st7703-request-higher-pixelclock-for-RGB30.patch`**: Powkiddy RGB30 pixel clock adjustment.
* **`0012-arm64-dts-rockchip-update-powkiddy-x55-dts-to-suppor.patch`**: Powkiddy x55 specific patch.
* **`0016-arm64-dts-rockchip-add-device-tree-for-powkiddy-x35s.patch`**: Powkiddy x35s device tree addition.
* **`0018-arm64-dts-rockchip-add-device-tree-for-powkiddy-rgb2.patch`**: Powkiddy rgb20 device tree addition.
