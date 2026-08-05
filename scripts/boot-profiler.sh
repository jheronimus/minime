#!/bin/sh
# shellcheck shell=sh
# Minime boot profiler - on-device observer.
#
# Development tool only.  Not part of the normal image; it is injected into
# the initramfs by scripts/boot-profile.sh (cpio surgery - no full image
# rebuild) and removed again with `scripts/boot-profile.sh restore`.
#
# Runs as a background process started by the instrumented /init and appends
# a boot-relative timeline of boot events (seconds since the kernel started,
# read from /proc/uptime) to boot-profile.log on the FAT partition.
#
# Survives switch_root by anchoring on the FAT partition: the initramfs mounts
# the card at /mnt/card and /init later moves that mount to /mnt/sdcard in the
# new root (initramfs-init.sh: "mount -o move /mnt/card /mnt/system/mnt/sdcard").
# The observer `cd`s into the FAT mount once and stays there; the cwd follows
# the mount across the pivot, so relative paths keep resolving while absolute
# paths die with the deleted initramfs root:
#
#   ./boot.log, ./boot-profile.log  -> FAT (same file both sides of the pivot)
#   ../../proc, ../../sys, ../../bin -> the running root's view of kernel
#   interfaces (initramfs root pre-pivot, new root post-pivot)
#
# NB: no pipelines anywhere.  A `cmd | while read` pipe deadlocks and busy-
# loops the busybox observer after switch_root; all reads use direct
# redirection (<file, >file, <&N).

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# busybox: prefer the static build.  The initramfs ships its copy as /bin/busybox
# and the new root keeps /bin/busybox.static (the dynamic /bin/busybox cannot be
# exec'd by this observer post-pivot - its interpreter path is gone).  Resolved
# relative to the FAT cwd so it works on both sides of the pivot.
B() {
	if [ -x ../../bin/busybox.static ]; then
		../../bin/busybox.static "$@"
	elif [ -x ../../bin/busybox ]; then
		../../bin/busybox "$@"
	else
		/bin/busybox "$@"
	fi
}

# ---- configuration --------------------------------------------------------
SLEEP=0.2   # poll interval in seconds
TIMEOUT=120 # stop after this many seconds of uptime
# ftpd only forks per connection; tcpsvd is the persistent FTP service.
WATCH_PROC="tcpsvd telnetd wpa_supplicant udhcpc bluetoothd bluealsa dbus-daemon ntpd minui.elf keymon.elf minarch.elf"
WATCH_MOD="cfg80211 mac80211 rtw88_core rtw88_sdio rtw88_8821cs mali panfrost"

# ---- helpers ----------------------------------------------------------------
# Uptime via /proc/uptime, resolved from the FAT cwd (../../ is the running
# root on both sides of the pivot).
UPTIME=0
up() {
	read -r UPTIME _ <../../proc/uptime 2>/dev/null || UPTIME=0
}

mark() {
	up
	printf '%.2f %s\n' "$UPTIME" "$*" >>./boot-profile.log 2>/dev/null || true
}

# ---- state -------------------------------------------------------------------
# Anchor on the FAT mount: /init mounts it at /mnt/card pre-pivot and moves the
# same mount to /mnt/sdcard post-pivot, so cwd tracks it across switch_root.
# From the FAT root, ./ = FAT files and ../.. = the running root.
cd /mnt/card 2>/dev/null || cd /mnt/sdcard 2>/dev/null || true
# The UI launcher (launch.sh) redirects minui.elf output to
# .userdata/minime/logs/minui.txt, but that file survives a reboot, so a
# leftover from the previous session would fire ui:ready instantly.  Clear it
# before the current boot's UI starts so ui:ready only fires on a fresh file.
B rm -f ./.userdata/minime/logs/minui.txt 2>/dev/null || true

mark "boot:start"

SEEN_PROCS=""
SEEN_MODS=""
BOOTLOG_LINES=""
FB_UNBLANK=""
SWITCHED=""
OPENRC=""
UI_READY=""
FIRST=1

while :; do
	up

	_secs=$(printf '%.0f' "$UPTIME" 2>/dev/null || echo 0)
	if [ "$_secs" -ge "$TIMEOUT" ]; then
		mark "boot:timeout"
		break
	fi

	# PID 1 transitions: /init -> switch_root -> /sbin/init (openrc).
	_p1=$(B tr '\000' ' ' <../../proc/1/cmdline 2>/dev/null)
	case "$_p1" in
	*switch_root*)
		[ -z "$SWITCHED" ] && {
			mark "phase:switch-root"
			SWITCHED=1
		}
		;;
	*/sbin/init*)
		[ -z "$OPENRC" ] && {
			mark "phase:openrc"
			OPENRC=1
		}
		;;
	esac

	# fb-unblank service: framebuffer went from blanked to 0.
	if [ -z "$FB_UNBLANK" ]; then
		_bl=$(B cat ../../sys/class/graphics/fb0/blank 2>/dev/null)
		if [ "$_bl" = "0" ]; then
			mark "service:fb-unblank"
			FB_UNBLANK=1
		fi
	fi

	# boot.log growth: align wall-clock markers to uptime.  sed writes to a
	# temp file, then a redirected while-loop reads it back - no pipes.
	if [ -r ./boot.log ]; then
		_cur=$(B wc -l <./boot.log 2>/dev/null || echo 0)
		if [ "$FIRST" = "1" ]; then
			BOOTLOG_LINES=$_cur
			FIRST=0
		elif [ -n "$BOOTLOG_LINES" ] && [ "$_cur" -gt "$BOOTLOG_LINES" ]; then
			up
			B sed -n "$((BOOTLOG_LINES + 1)),${_cur}p" ./boot.log 2>/dev/null >./.boot-profiler.tmp
			while IFS= read -r _line || [ -n "$_line" ]; do
				case "$_line" in
				*"Moving mounts and switching root"*)
					# the poll may miss the brief switch_root exec window
					[ -z "$SWITCHED" ] && {
						mark "phase:switch-root"
						SWITCHED=1
					}
					;;
				esac
				printf '%.2f log %s\n' "$UPTIME" "$_line" >>./boot-profile.log 2>/dev/null || true
			done <./.boot-profiler.tmp
			BOOTLOG_LINES=$_cur
		fi
	fi

	# Processes: match the watch list against /proc/<pid>/comm directly
	# (<=15 chars, all watched names fit).  grep -q across the whole glob is
	# one invocation per watched name and cannot block like a cmdline read.
	if [ -z "$UI_READY" ]; then
		for _p in $WATCH_PROC; do
			case " $SEEN_PROCS " in
			*" $_p "*) continue ;;
			esac
			if B grep -qx "$_p" ../../proc/[0-9]*/comm 2>/dev/null; then
				mark "proc:$_p"
				SEEN_PROCS="$SEEN_PROCS $_p"
			fi
		done
	fi

	# Kernel modules: effects of the modules + gpudriver services.
	if [ -z "$UI_READY" ]; then
		for _m in $WATCH_MOD; do
			case " $SEEN_MODS " in
			*" $_m "*) continue ;;
			esac
			if B grep -q "^$_m " ../../proc/modules 2>/dev/null; then
				mark "mod:$_m"
				SEEN_MODS="$SEEN_MODS $_m"
			fi
		done
	fi

	# UI ready: fresh launcher session log appeared while minui.elf runs.
	if [ -z "$UI_READY" ] && [ -f ./.userdata/minime/logs/minui.txt ]; then
		mark "ui:ready"
		UI_READY=1
	fi

	B sleep "$SLEEP" 2>/dev/null || true
done
mark "boot:end"
B rm -f ./.boot-profiler.tmp 2>/dev/null || true
