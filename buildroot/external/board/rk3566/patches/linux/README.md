# Linux Kernel Patches for RK3566 Handhelds

These patches are applied to the mainline Linux kernel (`7.0.10`) during the Buildroot compilation process.

## Source Reference
The hardware and board support patches were imported from the **[ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)** project:
- **Repository URL**: `https://github.com/ROCKNIX/distribution`
- **Imported Commit**: `61f7ff705bc3515f91757876a6cf9bdf483789ea`
- **Description**: Mainline kernel display/backlight/PHY/DTS patches for Anbernic RK3566-based devices.

## Omitted Patches
To ensure a mainline-clean and highly optimized system, we have omitted several patches that are specific only to Powkiddy or non-Anbernic devices:
* **`0005-arm64-dts-rockchip-fixup-anbernic-controls.patch`**: Omitted to use mainline kernel `gpio-keys` and standard `adc-joystick` input systems instead of Rocknix's custom out-of-tree joypad driver.
* **`0009-arm64-dts-rockchip-fix-shoulders-triggers-on-powkidd.patch`**: Powkiddy-specific hardware button fixes.
* **`0010-drm-panel-st7703-request-higher-pixelclock-for-RGB30.patch`**: Powkiddy RGB30 pixel clock adjustment.
* **`0012-arm64-dts-rockchip-update-powkiddy-x55-dts-to-suppor.patch`**: Powkiddy x55 specific patch.
* **`0016-arm64-dts-rockchip-add-device-tree-for-powkiddy-x35s.patch`**: Powkiddy x35s device tree addition.
* **`0018-arm64-dts-rockchip-add-device-tree-for-powkiddy-rgb2.patch`**: Powkiddy rgb20 device tree addition.


## Mainline Kernel 7.0.10 Adaptation Changes

During the migration and build stabilization for mainline kernel `7.0.10`, several imported patches were refactored or rewritten to align with strict `--fuzz=0` Buildroot criteria and the upstream kernel's device tree / driver evolution (particularly around SCMI clocks and NVMEM layout changes):

* **`0002-power-supply-rk817-update-battery-and-charger-name-s.patch`**: Streamlined to focus exclusively on updating the `rk817` battery descriptor name (to `battery`), resolving name matching in modern system drivers for EmulationStation.
* **`0008-arm64-dts-rockchip-add-support-for-mali-bifrost-driv.patch`**: Adjusted to reference the modern `SCMI_CLK_GPU` identifier for GPU clocks in mainline kernel device trees.
* **`0019-arm64-dts-rockchip-add-system-power-controller-attri.patch`**: Simplified and aligned with the `rk3566-anbernic-rgxx3.dtsi` PMIC (`rk817`) structure.
* **`0022-nvmem-rockchip-otp-Add-support-for-rk3568-otp.patch`**: Rewritten and mathematically aligned to match the exact context structure of the Rockchip OTP driver in `7.0.10` to satisfy `--fuzz=0` rules.
* **`1001-arm64-dts-rockchip-Add-idle-states-for-rk356x.patch`**: Refactored to target the flat DTS nodes and align with SCMI clock descriptors (`SCMI_CLK_CPU`) in the `7.0.10` device tree base, enabling standard low-power CPU sleep states.
