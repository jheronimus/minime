# RK3566 Kernel Options

## Scope

Enable 18 requested Rocknix-derived kernel options for RK3566 plus the mandatory Cortex-A55 AFDBM workaround. Keep `schedutil` as the default CPU frequency governor while making `performance` available for runtime selection.

## Configuration

Add these options to `minime/external/board/rk3566/tiny-rk3566.config`:

- `CONFIG_ARM64_ERRATUM_1024718=y`
- `CONFIG_ARM64_ERRATUM_1530923=y`
- `CONFIG_ARM64_ERRATUM_2441007=y`
- `CONFIG_ARM64_HW_AFDBM=y`
- `CONFIG_ARM64_CNP=y`
- `CONFIG_ARM64_AMU_EXTN=y`
- `CONFIG_NVMEM_ROCKCHIP_OTP=y`
- `CONFIG_RTC_DRV_RK808=y`
- `CONFIG_RTC_HCTOSYS=y`
- `CONFIG_RTC_SYSTOHC=y`
- `CONFIG_SCHED_MC=y`
- `CONFIG_COMPACTION=y`
- `CONFIG_HWMON=y`
- `CONFIG_IKCONFIG=y`
- `CONFIG_IKCONFIG_PROC=y`
- `CONFIG_DETECT_HUNG_TASK=y`
- `CONFIG_WATCHDOG=y`
- `CONFIG_DW_WATCHDOG=y`
- `CONFIG_CPU_FREQ_GOV_PERFORMANCE=y`

Do not enable `CONFIG_ROCKCHIP_ERRATUM_3568002`; the target has 2 GB RAM. Do not change `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`.

## Runtime Behavior

Kernel DesignWare watchdog support will be available through `/dev/watchdog`, but no userspace watchdog daemon will be enabled. `CONFIG_ARM64_AMU_EXTN` requires a device boot test because incompatible BL31 firmware can cause a panic or lockup.

## Verification

1. Resolve the Linux 7.0.10 RK3566 config and confirm all 19 symbols have the requested values.
2. Run `git diff --check`.
3. Use the remote RK3566 build workflow; do not compile firmware locally.
4. On device, verify boot, Mali loading, RTC, OTP NVMEM, `/proc/config.gz`, and `/dev/watchdog`.
5. Check `dmesg` for AMU, Cortex-A55 workaround, GIC, RTC, NVMEM, watchdog, and Mali errors.
