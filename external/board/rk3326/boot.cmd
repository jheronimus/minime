setenv bootargs console=ttyS2,1500000 console=tty0 root=/dev/mmcblk0p1 rootfstype=erofs rootwait pm_async=off ignore_loglevel loglevel=7 printk.devkmsg=on consoleblank=0 vt.global_cursor_default=1 rtw88_core.disable_lps_deep=Y
erofsload mmc 0:1 ${kernel_addr_r} Image
erofsload mmc 0:1 ${fdt_addr_r} rk3326-anbernic-rg351v.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
