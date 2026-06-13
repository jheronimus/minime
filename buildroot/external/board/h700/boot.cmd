setenv bootargs console=ttyS0,115200 console=tty1 root=/dev/ram0 rdinit=/init rootwait pm_async=off ignore_loglevel loglevel=7 printk.devkmsg=on consoleblank=0 vt.global_cursor_default=0 rtw88_core.disable_lps_deep=Y cma=128M drm_kms_helper.drm_fbdev_overalloc=200
setenv default_device sun50i-h700-anbernic-rg35xx-sp.dtb
setenv device auto
fatload mmc 0:1 ${scriptaddr} .minime/config/device.cfg && env import -t ${scriptaddr} ${filesize}
if test "${device}" = "auto"; then
	if test -n "${fdtfile}"; then
		setenv device "${fdtfile}"
	else
		setenv device "${default_device}"
	fi
fi
fatload mmc 0:1 ${kernel_addr_r} .minime/kernel
fatload mmc 0:1 ${fdt_addr_r} .minime/devices/${device}
fatload mmc 0:1 ${ramdisk_addr_r} .minime/initramfs
booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
