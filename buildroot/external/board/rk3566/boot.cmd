setenv bootargs console=ttyS2,1500000 console=tty0 root=/dev/ram0 rdinit=/init rootwait pm_async=off ignore_loglevel loglevel=7 printk.devkmsg=on consoleblank=0 vt.global_cursor_default=1 fbcon=rotate:3 rtw88_core.disable_lps_deep=Y pstore_blk.blkdev=PARTUUID=6f2de7ab-8764-4d2f-9253-9db2a7a57718 pstore_blk.kmsg_size=64 pstore_blk.console_size=512 best_effort=y
setenv bootdevtype mmc
setenv bootdevnum 0:1
if test -n "${devtype}" && test -n "${devnum}" && test -n "${distro_bootpart}"; then
	setenv bootdevtype "${devtype}"
	setenv bootdevnum "${devnum}:${distro_bootpart}"
fi
setenv bootlog "minime uboot: start dev=${bootdevtype} ${bootdevnum} fdtfile=${fdtfile}"
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-00-start.log ${filesize}
setenv default_device rk3566-anbernic-rg-arc-d.dtb
setenv device auto
if fatload ${bootdevtype} ${bootdevnum} ${scriptaddr} .system/config/device.cfg; then
	env import -t ${scriptaddr} ${filesize}
	setenv bootlog "minime uboot: loaded device.cfg device=${device}"
else
	setenv bootlog "minime uboot: missing device.cfg, using fallback"
fi
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-01-device-cfg.log ${filesize}
if test "${device}" = "auto"; then
	if test -n "${fdtfile}"; then
		setenv device "${fdtfile}"
	else
		setenv device "${default_device}"
	fi
fi
setenv bootlog "minime uboot: selected device=${device}"
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-02-device.log ${filesize}
if fatload ${bootdevtype} ${bootdevnum} ${kernel_addr_r} tinykernel; then
	setenv bootlog "minime uboot: loaded tinykernel bytes=${filesize}"
else
	setenv bootlog "minime uboot: ERROR failed to load tinykernel from ${bootdevtype} ${bootdevnum}"
	env export -t ${scriptaddr} bootlog
	fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-90-kernel-fail.log ${filesize}
	sleep 5
	reset
fi
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-03-kernel.log ${filesize}
if fatload ${bootdevtype} ${bootdevnum} ${fdt_addr_r} .system/devices/${device}; then
	setenv bootlog "minime uboot: loaded dtb=.system/devices/${device} bytes=${filesize}"
else
	setenv bootlog "minime uboot: ERROR failed to load dtb=.system/devices/${device} from ${bootdevtype} ${bootdevnum}"
	env export -t ${scriptaddr} bootlog
	fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-91-dtb-fail.log ${filesize}
	sleep 5
	reset
fi
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-04-dtb.log ${filesize}
if fatload ${bootdevtype} ${bootdevnum} ${ramdisk_addr_r} .system/initrd.img; then
	setenv initrd_size ${filesize}
	setenv bootlog "minime uboot: loaded initrd bytes=${initrd_size}"
else
	setenv bootlog "minime uboot: ERROR failed to load .system/initrd.img from ${bootdevtype} ${bootdevnum}"
	env export -t ${scriptaddr} bootlog
	fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-92-initrd-fail.log ${filesize}
	sleep 5
	reset
fi
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-05-initrd.log ${filesize}
fdt addr ${fdt_addr_r}
fdt resize
fdt set /chosen bootargs "${bootargs}"
fdt chosen ${ramdisk_addr_r} ${initrd_size}
setenv bootlog "minime uboot: calling booti kernel=${kernel_addr_r} fdt=${fdt_addr_r} initrd=${ramdisk_addr_r}:${initrd_size}"
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-06-booti.log ${filesize}
booti ${kernel_addr_r} ${ramdisk_addr_r}:${initrd_size} ${fdt_addr_r}
setenv bootlog "minime uboot: ERROR booti returned"
env export -t ${scriptaddr} bootlog
fatwrite ${bootdevtype} ${bootdevnum} ${scriptaddr} minime-uboot-93-booti-returned.log ${filesize}
