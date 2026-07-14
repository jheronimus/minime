# RK3566 Kernel Configuration: Minime vs. ROCKNIX

This document provides a comparative analysis of the combined kernel configuration used by **Minime** (`tiny-base.config` + `tiny-rk3566.config`) against the kernel configuration utilized by the **ROCKNIX** distribution for Rockchip RK3566 retro-gaming handheld devices, with a specific focus on the **Anbernic RG Arc D** hardware.

---

## 1. Hardware Support (Anbernic RG Arc D)

The Anbernic RG Arc D features a Sega Saturn controller layout, dual boot capability, dual-band Wi-Fi/Bluetooth, and a 4-inch 640x480 touchscreen panel. The kernel configurations for these systems manage hardware support as follows:

| Hardware Component | Minime Combined Config | ROCKNIX Config | Analysis for RG Arc D |
| :--- | :--- | :--- | :--- |
| **Touchscreen Controller** | *Disabled*<br>`# CONFIG_INPUT_TOUCHSCREEN` | **Enabled**<br>`CONFIG_INPUT_TOUCHSCREEN=y`<br>`CONFIG_TOUCHSCREEN_GOODIX=y` | **Needed on Arc D.** The RG Arc D uses a Goodix GT927 touchscreen controller on `i2c2` (address `0x14`). ROCKNIX supports touchscreen navigation, while Minime's current kernel cannot receive touch events. (Note: The sibling Arc S has no touchscreen). |
| **Wi-Fi & Bluetooth** | **Enabled**<br>`CONFIG_RTW88=y`<br>`CONFIG_RTW88_8821CS=y`<br>`CONFIG_BT_HCIUART_RTL=y` | **Enabled**<br>Same drivers | **Identical support.** Both systems support the onboard Realtek RTL8821CS SDIO Wi-Fi and UART Bluetooth module. Minime disables deep sleep via bootargs (`rtw88_core.disable_lps_deep=Y`) to eliminate latency spikes. |
| **HDMI Output** | **Enabled**<br>`CONFIG_ROCKCHIP_VOP2=y`<br>`CONFIG_ROCKCHIP_DW_HDMI=y` | **Enabled**<br>Same drivers | **Identical support.** Both support external displays via Rockchip VOP2 and the DesignWare HDMI block. |
| **PMIC & Audio Codec** | **Enabled**<br>`CONFIG_MFD_RK8XX=y`<br>`CONFIG_REGULATOR_RK808=y`<br>`CONFIG_CHARGER_RK817=y`<br>`CONFIG_SND_SOC_RK817=y` | **Enabled**<br>Same drivers | **Identical support.** Both systems support the RK817 PMIC, charger regulator, and its integrated stereo audio codec (channels are reversed in the DTSI and handled via sound configuration). |
| **MODE Button** | **Enabled**<br>`CONFIG_ROCKCHIP_SARADC=y`<br>`CONFIG_KEYBOARD_ADC=y` | **Enabled**<br>Same drivers | **Identical support.** The special MODE button is routed via the Rockchip Successive Approximation Register ADC (SARADC) channel 0, mapped as `BTN_MODE`. |
| **Saturn D-Pad & 6 Face Buttons** | **Enabled**<br>`CONFIG_KEYBOARD_GPIO=y`<br>`CONFIG_INPUT_KEYBOARD=y` | **Enabled**<br>Same drivers | **Identical support.** The Saturn D-pad, 6 face buttons, L1/L2, R1/R2, Select, and Start are mapped as standard GPIO keys in the device tree. |
| **Vibration Motor** | *Disabled*<br>`# CONFIG_INPUT_PWM_VIBRA` | **Enabled/Noop**<br>`CONFIG_INPUT_PWM_VIBRA=y` | **Physically non-functional.** While Anbernic lists a vibration motor in spec sheets and ROCKNIX compile-enables it, hardware teardowns reveal no motor is soldered or connected. Omit driver to save space. |

---

## 2. Performance Improvements

Performance configurations affect kernel scheduling, errata workarounds, and CPU-bound emulators:

| Feature / Config | Minime Combined Config | ROCKNIX Config | Impact & Analysis |
| :--- | :--- | :--- | :--- |
| **Energy Model & EAS** | *Disabled*<br>`# CONFIG_ENERGY_MODEL`<br>`# CONFIG_THERMAL_OF` | **Enabled**<br>`CONFIG_ENERGY_MODEL=y`<br>`CONFIG_THERMAL_OF=y` | **Blocked in Minime due to proprietary Mali driver.** ROCKNIX uses the mainline open-source **Panfrost** GPU driver, allowing EAS integration. Minime uses the out-of-tree **Mali blob (`mali_kbase`)**, which experiences a kernel boot hang (`em_create()`) when dynamic cooling cooling-devices register with the energy-model. |
| **Cortex-A55 Errata Workarounds** | **Enabled**<br>Cortex-A55 workarounds and `CONFIG_ARM64_HW_AFDBM=y` | **Enabled**<br>Same workarounds | **Crucial stability.** Both enable critical ARM errata workarounds (including Cortex-A55 AFDBM, CNP, and AMU extensions) to prevent core lockups under heavy CPU loads. |
| **CPU Frequency Governors** | **Enabled**<br>`CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y`<br>`CONFIG_CPU_FREQ_GOV_PERFORMANCE=y` | **Enabled**<br>Same governors | **Identical options.** Both use `schedutil` as the default governor for smart scaling, with `performance` available for runtime pinning via the UI. |
| **Memory Manager (MGLRU)** | **Enabled + Custom Tuned**<br>`CONFIG_LRU_GEN=y`<br>`CONFIG_LRU_GEN_ENABLED=y` | **Enabled + Default Tuned** | **Minime has better latency spikes protection.** Minime implements aggressive sysctl configurations (`vm.swappiness=30`, `vm.page-cluster=0`, `vm.watermark_scale_factor=150`) to prevent zram page allocation storms from starving the GPU under low-memory emulation scenarios. |

---

## 3. Power Management Improvements

Power efficiency and thermal profiles are critical for passive cooling and battery life:

| Feature / Config | Minime Combined Config | ROCKNIX Config | Impact & Analysis |
| :--- | :--- | :--- | :--- |
| **DDR DMC Scaling** | **Enabled + Governor Cooldown**<br>`CONFIG_PM_DEVFREQ=y`<br>`CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI=y` | **Enabled + Aggressive** | **Minime is more stable.** Both scale DDR clock dynamically (324Mhz idle to 1056Mhz load). However, ROCKNIX suffered level-load crashes due to rapid frequency transitions. Minime implements a mandatory **100ms HWFFC transition cooldown** and a 15% upscale threshold to protect system integrity during burst allocations. |
| **TEO Idle Governor** | **Enabled**<br>`CONFIG_CPU_IDLE_GOV_TEO=y` | **Enabled**<br>`CONFIG_CPU_IDLE_GOV_TEO=y` | **Identical.** TEO replaces the legacy `menu` governor to provide better idle-state prediction for bursty, interactive gaming workloads. |
| **GPU Power Gating** | **Enabled** (`coarse_demand`) | **Enabled** (`coarse_demand`) | **Identical.** Mali-G52 cores gate/power down completely between frame submissions to conserve battery. |
| **CPU Undervolting** | **Enabled (Opt-in)**<br>Boot-time DTBO overlays (`l1`/`l2`/`l3`) | **Enabled (Opt-in)** | **Identical.** Allows users to reduce voltage step tables at boot. Aggressive undervolting (L3) saves ~1W of power and reduces CPU temp by up to 18°C under load, enabling sustained 1800Mhz turbo operation. |
| **KMS Plane Scaling** | **Enabled (Userspace/KMS)** | **Enabled (Userspace/KMS)** | **Identical.** GPU workload upscaling is handled directly by the VOP2 display controller planes rather than the resource-heavy RGA hardware, saving up to 30% battery in GPU-bound emulators (e.g. N64). |
| **Suspend Power State** | **Enabled**<br>Suspend floor of ~0.089W | **Enabled**<br>Same | Both systems successfully spin down memory controllers, CPU cores, and PMIC domains during system sleep. |

---

## 4. Debugging Only

Options enabled strictly for debugging, auditing, or crash telemetry:

| Config Option | Minime Combined Config | ROCKNIX Config | Impact & Analysis |
| :--- | :--- | :--- | :--- |
| **`CONFIG_IKCONFIG`** & **`CONFIG_IKCONFIG_PROC`** | **Enabled** | **Enabled** | Exposes the running kernel configuration under `/proc/config.gz`. Highly useful for auditing and ensuring build parity. |
| **`CONFIG_PSTORE`** & **`CONFIG_PSTORE_RAM`** | **Enabled** | **Enabled** | Reserves a 1MB ramoops buffer in DTS. Captures oops and kernel panics across warm reboots to diagnose crash events. |
| **`CONFIG_MAGIC_SYSRQ`** | **Enabled** | *Disabled* | Allows triggering a controlled kernel panic via sysrq (e.g. `echo c > /proc/sysrq-trigger`) to verify pstore recovery pipelines. Can be disabled in production. |
| **`CONFIG_DETECT_HUNG_TASK`** | **Enabled** | **Enabled** | Automatically monitors and logs processes blocked in D-state for more than 120s. |

---

## 5. Enabled in ROCKNIX, but Useless or Harmful in Minime

These configurations are included in ROCKNIX but offer no benefit to Minime, or are actively harmful to its performance-focused architecture:

1. **`CONFIG_DRM_PANFROST=y` (Useless / Conflict)**
   * *ROCKNIX:* Enabled to power its open-source graphics stack.
   * *Minime:* Not needed. Minime relies on the proprietary Arm `libmali` user-space driver and matching `mali_kbase` kernel module for maximum GPU efficiency in GLES/Vulkan. Compiling Panfrost adds bloat and can cause display pipeline binding conflicts at boot.
2. **`CONFIG_ENERGY_MODEL=y` (Actively Harmful)**
   * *ROCKNIX:* Enabled for Energy-Aware Scheduling (EAS).
   * *Minime:* Disabled. Out-of-tree dynamic voltage coefficient hooks in `mali_kbase` clash with the mainline kernel's `em_create()` model generation, causing a hard hang during GPU driver initialization at boot.
3. **`CONFIG_ROCKCHIP_ERRATUM_3568002` (Useless)**
   * *ROCKNIX:* Enable-checked in their general config.
   * *Minime:* Disabled. This erratum targets RK3566/RK3568 memory controllers handling memory configurations with large RAM pools (>4GB). The Anbernic RG Arc D only features 2GB of LPDDR4, making this workaround entirely redundant.
4. **`CONFIG_CPU_FREQ_GOV_ONDEMAND=y` (Useless)**
   * *ROCKNIX:* Enabled.
   * *Minime:* Useless. The modern Arm SCMI frequency scaling layer performs optimally with `schedutil` and `performance`. Legacy governors like `ondemand` lack direct scheduler-load integration and are dead weight.
5. **USB Dongles, External Adapters, and Network Filesystem Drivers (Bloat)**
   * *ROCKNIX:* Compiles dozens of drivers for USB Ethernet adapters, Realtek/Mediatek USB Wi-Fi dongles, CIFS/SMB, NFS, etc.
   * *Minime:* Disabled. Minime targets a minimal rootfs footprint for standalone play. It connects to Wi-Fi exclusively using the internal SDIO chip and does not support heavy desktop network filesystems.
