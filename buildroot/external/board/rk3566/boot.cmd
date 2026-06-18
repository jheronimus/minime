setenv bootargs console=ttyS2,1500000 console=tty0 root=/dev/ram0 rdinit=/init rootwait pm_async=off consoleblank=0 vt.global_cursor_default=1 fbcon=rotate:1 rtw88_core.disable_lps_deep=Y
setenv bootdevtype mmc
setenv bootdevnum 0:1
if test -n "${devtype}" && test -n "${devnum}" && test -n "${distro_bootpart}"; then
	setenv bootdevtype "${devtype}"
	setenv bootdevnum "${devnum}:${distro_bootpart}"
fi
setenv default_device rk3566-anbernic-rg-arc-d.dtb
setenv device auto
if fatload ${bootdevtype} ${bootdevnum} ${scriptaddr} .minime/config/device.cfg; then
	env import -t ${scriptaddr} ${filesize}
fi
if test "${device}" = "auto"; then
	if test -n "${fdtfile}"; then
		setenv device "${fdtfile}"
	else
		setenv device "${default_device}"
	fi
fi
if fatload ${bootdevtype} ${bootdevnum} ${kernel_addr_r} .minime/kernel; then
	echo "Loaded .minime/kernel"
else
	echo "Failed to load .minime/kernel"
	sleep 5
	reset
fi
if fatload ${bootdevtype} ${bootdevnum} ${fdt_addr_r} .minime/devices/${device}; then
	echo "Loaded .minime/devices/${device}"
else
	echo "Failed to load .minime/devices/${device}"
	sleep 5
	reset
fi
if fatload ${bootdevtype} ${bootdevnum} ${ramdisk_addr_r} .minime/initramfs; then
	setenv initrd_size ${filesize}
else
	echo "Failed to load .minime/initramfs"
	sleep 5
	reset
fi
fdt addr ${fdt_addr_r}
fdt resize
if test "${undervolt}" = "l1" -o "${undervolt}" = "l2" -o "${undervolt}" = "l3"; then
	if fatload ${bootdevtype} ${bootdevnum} ${scriptaddr} .minime/overlays/rk3566-undervolt-cpu-${undervolt}.dtbo; then
		fdt apply ${scriptaddr}
		echo "Applied CPU undervolt ${undervolt} overlay"
	else
		echo "WARNING: undervolt=${undervolt} but overlay not found, continuing at stock voltage"
	fi
else
	echo "CPU undervolt off (undervolt=${undervolt})"
fi
fdt set /chosen bootargs "${bootargs}"
fdt chosen ${ramdisk_addr_r} ${initrd_size}
booti ${kernel_addr_r} ${ramdisk_addr_r}:${initrd_size} ${fdt_addr_r}
sleep 5
reset
