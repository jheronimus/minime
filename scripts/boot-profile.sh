#!/usr/bin/env bash
# shellcheck shell=bash
# Minime boot profiler - host-side tool.
#
# Profiles the non-first boot of a live device WITHOUT rebuilding an image.
# The stock testing initramfs is instrumented locally (cpio surgery - the
# on-device observer scripts/boot-profiler.sh is added and the
# /init hook that starts it is inserted), the modified .minime/initramfs is
# pushed straight to the device over FTP, and the device reboots.  No CI run
# is required for any step; only the final, verified result needs a CI build.
#
#   baseline                       parse the last boot out of the existing
#                                  /mnt/sdcard/boot.log (non-invasive, no reboot)
#   inject [os board ui] [ip]      instrument initramfs, push, reboot
#   collect [ip]                   pull boot-profile.log, print timeline + report
#   restore [os board ui] [ip]     push back the stock initramfs, reboot
#
# Defaults: alpine h700 minui; target IP read from deploy.cfg.
# Optionally pass `--ota` to inject/restore to deliver via a rebuilt OTA
# package instead of a direct FTP upload of the initramfs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
OBSERVER="$ROOT/scripts/boot-profiler.sh"
IP_FROM_CFG=""

if [ -f "$ROOT/deploy.cfg" ]; then
	IP_FROM_CFG=$(grep -E '^\s*target_ip=' "$ROOT/deploy.cfg" | head -n1 | cut -d'=' -f2- | tr -d ' "\r')
fi

log() { printf '[boot-profile] %s\n' "$*" >&2; }
die() {
	log "ERROR: $*"
	exit 1
}

# --------------------------------------------------------------------------
# Argument parsing: [os board ui] [ip], --ota anywhere.
# --------------------------------------------------------------------------
OS="alpine"
BOARD="h700"
UI="minui"
IP=""
OTA=0
DEBUG=0

parse_args() {
	POS=()
	for a in "$@"; do
		case "$a" in
		--ota) OTA=1 ;;
		--debug) DEBUG=1 ;;
		[0-9]*.[0-9]*.[0-9]*.[0-9]*) IP="$a" ;;
		*) POS+=("$a") ;;
		esac
	done
	[ "${#POS[@]}" -ge 1 ] && OS="${POS[0]}"
	[ "${#POS[@]}" -ge 2 ] && BOARD="${POS[1]}"
	[ "${#POS[@]}" -ge 3 ] && UI="${POS[2]}"
	[ -z "$IP" ] && IP="$IP_FROM_CFG"
	if [ -z "$IP" ]; then
		die "no target IP (pass it or set target_ip= in deploy.cfg)"
	fi
}

triple() { printf '%s-%s-%s' "$OS" "$BOARD" "$UI"; }
workspace() {
	printf '%s/downloads/boot-profile/%s' "$ROOT" "$(triple)"
}

remote() {
	"$SCRIPTS/remote-cmd.sh" "$1" "$IP"
}

# --------------------------------------------------------------------------
# Stock OTA caching + initramfs extraction/instrumentation/repack.
# --------------------------------------------------------------------------
fetch_stock() {
	local ws="$1"
	local pkg="$ws/stock-ota.tar.xz"
	if [ ! -f "$pkg" ]; then
		log "fetching stock OTA minime-$(triple).tar.xz from testing..."
		local fetched
		fetched=$("$SCRIPTS/fetch-asset.sh" "minime-$(triple).tar.xz")
		cp "$fetched" "$pkg"
	else
		log "reusing cached stock OTA $pkg"
	fi
	printf '%s\n' "$pkg"
}

extract_stock_initramfs() {
	local ws="$1" stock="$2"
	rm -rf "$ws/stage" "$ws/initrd"
	mkdir -p "$ws/stage" "$ws/initrd"
	tar -xf "$stock" -C "$ws/stage"
	if [ ! -f "$ws/stage/.minime/initramfs" ]; then
		die "stock OTA has no .minime/initramfs"
	fi
	(
		cd "$ws/initrd" &&
			cpio -idm --quiet <"$ws/stage/.minime/initramfs"
	) 2>/dev/null
	[ -f "$ws/initrd/init" ] || die "initramfs has no /init"
}

instrument_initramfs() {
	local ws="$1"
	cp "$OBSERVER" "$ws/initrd/boot-profiler.sh"
	chmod 755 "$ws/initrd/boot-profiler.sh"
	python3 - "$ws/initrd/init" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")

anchor = 'log_card "[INITRAMFS] Initialized persistent logging on $CARD_DEV"'
idx = next((i for i, l in enumerate(lines) if anchor in l), None)
if idx is None:
    sys.exit("anchor line not found in initramfs /init")

hook = [
    "",
    "# --- boot profiler hook (scripts/boot-profile.sh inject) ---",
    "if [ -f /boot-profiler.sh ]; then",
    "\tcp -f /boot-profiler.sh /mnt/card/boot-profiler.sh 2>/dev/null || true",
    "\tif [ -f /mnt/card/.boot-profiler-debug ]; then",
    "\t\tsh -x /mnt/card/boot-profiler.sh >>/mnt/card/boot-profiler.trace 2>&1 &",
    "\telse",
    "\t\tsh /mnt/card/boot-profiler.sh 2>/dev/null &",
    "\tfi",
    "fi",
    "",
]
lines[idx + 1:idx + 1] = hook

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
PY
	sh -n "$ws/initrd/init" || die "patched /init failed sh -n"
}

repack_initramfs() {
	local ws="$1"
	local out="$ws/initramfs.instrumented"
	(
		cd "$ws/initrd" &&
			find . | cpio -o -H newc --quiet
	) >"$out" 2>/dev/null
	printf '%s\n' "$out"
}

# --------------------------------------------------------------------------
# Delivery + reboot.
# --------------------------------------------------------------------------
push_initramfs() {
	local ws="$1" initramfs="$2"
	log "uploading instrumented initramfs ($(du -h "$initramfs" | cut -f1)) over FTP..."
	if ! curl -s -S -u root: -T "$initramfs" "ftp://$IP/.minime/initramfs"; then
		die "direct FTP upload failed - re-run with --ota for the OTA delivery path"
	fi
}

push_via_ota() {
	local ws="$1"
	local triple_str
	triple_str="$(triple)"
	local pkg="$ws/minime-${triple_str}-profiler.tar.xz"
	log "rebuilding OTA from staged payload..."
	cp "$ws/initramfs.instrumented" "$ws/stage/.minime/initramfs"
	(
		cd "$ws/stage" &&
			tar -cf - . | xz -T0 -9 >"$pkg"
	)
	log "delivering OTA via update-device.sh..."
	"$SCRIPTS/update-device.sh" "$pkg" "$IP"
}

reboot_and_wait() {
	local ws="$1"
	remote "rm -f /mnt/sdcard/boot-profile.log /mnt/sdcard/boot-profiler.sh; sync; reboot" >/dev/null 2>&1 || true
	log "waiting for device to go down and come back..."
	local wall
	wall=$(
		python3 - "$IP" <<'PY'
import socket, sys, time

ip = sys.argv[1]
t0 = time.monotonic()
down = None
while time.monotonic() - t0 < 90:
    try:
        s = socket.create_connection((ip, 23), timeout=0.5)
        s.close()
        time.sleep(0.3)
    except OSError:
        down = time.monotonic() - t0
        break
    while True:
        try:
            s = socket.create_connection((ip, 23), timeout=0.5)
            s.close()
            break
        except OSError:
            if time.monotonic() - t0 > 180:
                sys.exit(1)
            time.sleep(0.3)
    up = time.monotonic() - t0
    if down is None:
        down = up
    # Host reaches the device over WiFi here, which is later than telnetd's
    # own start (telnetd binds at ~3.5s uptime but wifi+DHCP connects at
    # ~14s).  Capture the device uptime at the moment the host's connection
    # succeeds so pre-kernel (U-Boot + power-cycle) is wall - uptime.
    try:
        s = socket.create_connection((ip, 23), timeout=3)
        s.sendall(b"cat /proc/uptime\n")
        s.settimeout(3)
        data = b""
        deadline = time.monotonic() + 3
        import re
        m = None
        while time.monotonic() < deadline:
            data += s.recv(1024)
            # The telnet banner carries IAC negotiation bytes, so scrape the
            # two floats out of the "UPTIME IDLE" reply line instead of split().
            m = re.search(rb"(\d+\.\d+)\s+(\d+\.\d+)", data)
            if m:
                break
        s.close()
        dev_up = float(m.group(1)) if m else -1
    except (OSError, ValueError, IndexError):
        dev_up = -1
    print(f"{up:.1f} {up - down:.1f} {dev_up:.2f}")
PY
	) || die "device did not come back up"
	local up net dev_up
	read -r up net dev_up <<<"$wall"
	printf '%s\n' "$net" >"$ws/wall-to-telnet.txt"
	printf '%.2f\n' "$dev_up" >"$ws/device-uptime-at-connect.txt"
	log "device back up: ${up}s after reboot trigger, boot took ~${net}s (host wall clock, device uptime ${dev_up}s)"
}

# --------------------------------------------------------------------------
# Report generation.
# --------------------------------------------------------------------------
generate_report() {
	local ws="$1" profile="$2"
	local awkfile="$ws/report.awk"
	local wall=""
	[ -f "$ws/wall-to-telnet.txt" ] && wall=$(cat "$ws/wall-to-telnet.txt")
	cat >"$awkfile" <<'AWK'
function strip_log_time(s) {
    sub(/^log /, "", s)
    sub(/^\[[A-Za-z0-9_-]+ [0-9:]{8}\] /, "", s)
    return s
}
function lab(i) {
    s = ev[i]
    if (s ~ /^boot:start/) return "initramfs: FAT mounted (observer start)"
    if (s ~ /^phase:erofs-mounted/) return "initramfs: EROFS mounted"
    if (s ~ /^phase:switch-root/) return "initramfs: switch_root"
    if (s ~ /^phase:openrc/) return "openrc: PID1 (init) running"
    if (s ~ /^service:fb-unblank/) return "service: fb-unblank"
    if (s ~ /^proc:telnetd/) return "service: telnetd"
    if (s ~ /^proc:ftpd/) return "service: ftpd"
    if (s ~ /^proc:wpa_supplicant/) return "service: wifi (wpa_supplicant)"
    if (s ~ /^proc:udhcpc/) return "wifi: DHCP client (udhcpc)"
    if (s ~ /^proc:bluetoothd/) return "service: bluetooth (bluetoothd)"
    if (s ~ /^proc:bluealsa/) return "service: bluetooth (bluealsa)"
    if (s ~ /^proc:dbus-daemon/) return "service: dbus-daemon"
    if (s ~ /^proc:ntpd/) return "service: NTP (ntpd)"
    if (s ~ /^proc:minui.elf/) return "ui: MinUI frontend (minui.elf)"
    if (s ~ /^proc:keymon.elf/) return "ui: keymon"
    if (s ~ /^proc:minarch.elf/) return "ui: minarch"
    if (s ~ /^mod:cfg80211/) return "module: cfg80211"
    if (s ~ /^mod:mac80211/) return "module: mac80211"
    if (s ~ /^mod:rtw88_core/) return "module: rtw88_core"
    if (s ~ /^mod:rtw88_sdio/) return "module: rtw88_sdio"
    if (s ~ /^mod:rtw88_8821cs/) return "module: rtw88_8821cs"
    if (s ~ /^mod:mali/) return "module: mali (GPU)"
    if (s ~ /^mod:panfrost/) return "module: panfrost (GPU)"
    if (s ~ /^ui:ready/) return "ui: launcher log created (READY)"
    if (s ~ /^log.*\[TRAITS/) return "traits: " strip_log_time(s)
    if (s ~ /^log.*\[WIFI.*Waiting for WPA/) return "wifi: waiting for WPA handshake"
    if (s ~ /^log.*\[WIFI.*WPA handshake completed/) return "wifi: WPA handshake done"
    if (s ~ /^log.*\[WIFI.*Connection established/) return "wifi: DHCP lease / connected"
    if (s ~ /^log.*\[WIFI.*Starting background worker/) return "wifi: background worker started"
    if (s ~ /^log.*\[UI.*Executing/) return "ui: launch.sh executed"
    if (s ~ /^log \[INITRAMFS/) return "boot.log: " strip_log_time(s)
    if (s ~ /^log /) return "boot.log: " strip_log_time(s)
    return s
}
function find_first(re, out,    i) {
    for (i = 1; i <= n; i++) if (ev[i] ~ re) { out = t[i]; return 1 }
    return 0
}
function find_last(re, out,    i) {
    for (i = n; i >= 1; i--) if (ev[i] ~ re) { out = t[i]; return 1 }
    return 0
}
{
    if ($0 ~ /^[0-9.]+ boot:start/) {
        n = 0; inboot = 1
    }
    if (inboot == 0) next
    if ($0 ~ /boot:(end|timeout)/) { inboot = 0; next }
    if ($1 !~ /^[0-9]+(\.[0-9]+)?$/) next
    n++
    t[n] = $1 + 0
    ev[n] = substr($0, index($0, $2))
}
END {
    if (n == 0) { print "no profile data - was the device booted with an instrumented initramfs?"; exit 0 }
    printf "Minime boot profile (%d events, %.2fs poll granularity)\n", n, 0.2
    print "======================================================================"
    print "  uptime   delta  event"
    print "  -------  -----  ------------------------------------------------"
    prev = t[1]
    for (i = 1; i <= n; i++) {
        printf "  %7.2f  %5.2f  %s\n", t[i], t[i] - prev, lab(i)
        prev = t[i]
    }
    print "======================================================================"

    boot_start = t[1]
    sw = 0; openrc_t = 0; ui_ready = 0; ui_exec = 0
    find_first(/^phase:switch-root/, sw)
    find_first(/^phase:openrc/, openrc_t)
    find_first(/^ui:ready/, ui_ready)
    find_last(/^log.*\[UI.*Executing/, ui_exec)

    printf "phases:\n"
    if (sw > 0)  printf "  initramfs  FAT mounted -> switch_root   %6.2f s   (t=%.2f -> %.2f)\n", sw - boot_start, boot_start, sw
    if (openrc_t > 0 && ui_ready > 0) {
        printf "  openrc     init -> UI ready             %6.2f s   (t=%.2f -> %.2f)\n", ui_ready - openrc_t, openrc_t, ui_ready
    }
    if (ui_ready > 0) printf "  total      kernel start -> UI ready     %6.2f s   (uptime based)\n", ui_ready
    if (sw > 0 && openrc_t > 0) printf "  gap        switch_root -> openrc        %6.2f s\n", openrc_t - sw

    w1 = 0; w2 = 0; w3 = 0
    find_first(/^log.*\[WIFI.*Waiting for WPA/, w1)
    find_first(/^log.*\[WIFI.*WPA handshake completed/, w2)
    find_first(/^log.*\[WIFI.*Connection established/, w3)
    if (w1 > 0 && w2 > 0) printf "  wifi       wpa_supplicant up -> handshake %6.2f s\n", w2 - w1
    if (w2 > 0 && w3 > 0) printf "  wifi       handshake -> DHCP lease       %6.2f s\n", w3 - w2
    if (ui_exec > 0 && ui_ready > 0) printf "  ui         launch.sh -> launcher ready  %6.2f s\n", ui_ready - ui_exec

    if (wall != "") {
        printf "host        reset -> reachable (wall clock)  %6.2f s\n", wall
        if (dev_up > 0) {
            printf "             device uptime at connect %.2f s\n", dev_up
            printf "             U-Boot + power-cycle (pre-kernel) ~%.2f s\n", wall - dev_up
        }
    }

    for (i = 1; i <= 5; i++) { gapv[i] = 0; ga[i] = ""; gb[i] = "" }
    for (i = 2; i <= n; i++) {
        g = t[i] - t[i - 1]
        if (g <= 0.15) continue
        pos = 6
        for (j = 1; j <= 5; j++) if (g > gapv[j]) { pos = j; break }
        if (pos <= 5) {
            for (j = 5; j > pos; j--) { gapv[j] = gapv[j-1]; ga[j] = ga[j-1]; gb[j] = gb[j-1] }
            gapv[pos] = g; ga[pos] = lab(i - 1); gb[pos] = lab(i)
        }
    }
    print ""
    print "top gaps (>0.15s):  [longest first]"
    shown = 0
    for (i = 1; i <= 5; i++) {
        if (gapv[i] > 0) { printf "  %6.2f s  %s\n                -> %s\n", gapv[i], ga[i], gb[i]; shown = 1 }
    }
    if (shown == 0) print "  none"
}
AWK
	local dev_up=""
	[ -f "$ws/device-uptime-at-connect.txt" ] && dev_up=$(cat "$ws/device-uptime-at-connect.txt")
	awk -v wall="$wall" -v dev_up="$dev_up" -f "$awkfile" "$profile"
}

report_bootlog_last() {
	local ws="$1" bootlog="$2"
	local awkfile="$ws/bootlog-report.awk"
	cat >"$awkfile" <<'AWK'
function hm2sec(s, a) {
    split(s, a, ":")
    return a[1] * 3600 + a[2] * 60 + a[3]
}
$0 ~ /^\[INITRAMFS [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[INITRAMFS\] Mounted MINIME FAT partition/ {
    n = 0; inboot = 1
}
inboot {
    n++
    s = $0
    sub(/^\[[A-Za-z0-9_-]+ /, "", s)
    sub(/\] .*$/, "", s)
    t[n] = hm2sec(s)
    line[n] = $0
}
END {
    if (n == 0) { print "no boot markers found in boot.log"; exit 0 }
    printf "last boot from boot.log (wall clock; initramfs phase has an RTC skew jump):\n"
    base = t[1]
    prev = t[1]
    for (i = 1; i <= n; i++) {
        printf "  %5.0fs (%5.0fs)  %s\n", t[i] - base, t[i] - prev, line[i]
        prev = t[i]
    }
}
AWK
	awk -f "$awkfile" "$bootlog"
}

# --------------------------------------------------------------------------
# Commands.
# --------------------------------------------------------------------------
cmd_baseline() {
	local ws
	ws="$(workspace)"
	mkdir -p "$ws"
	log "baseline: parsing existing boot.log on device (no injection, no reboot)"
	if ! curl -s -u root: "ftp://$IP/boot.log" -o "$ws/boot.log"; then
		die "could not fetch boot.log from $IP"
	fi
	report_bootlog_last "$ws" "$ws/boot.log"
	log "for exact uptime-based timings run: ./scripts/boot-profile.sh inject"
}

cmd_inject() {
	local ws stock initramfs
	ws="$(workspace)"
	mkdir -p "$ws"
	stock="$(fetch_stock "$ws")"
	log "extracting stock initramfs..."
	extract_stock_initramfs "$ws" "$stock"
	log "instrumenting /init + adding observer..."
	instrument_initramfs "$ws"
	initramfs="$(repack_initramfs "$ws")"
	[ -f "$OBSERVER" ] || die "observer missing at $OBSERVER"
	log "instrumented initramfs ready ($(du -h "$initramfs" | cut -f1))"
	if [ "$OTA" -eq 1 ]; then
		push_via_ota "$ws"
	else
		push_initramfs "$ws" "$initramfs"
	fi
	if [ "$DEBUG" -eq 1 ]; then
		log "placing .boot-profiler-debug marker (observer will run under sh -x)"
		touch "$ws/debug.marker"
		curl -s -S -u root: -T "$ws/debug.marker" "ftp://$IP/.boot-profiler-debug"
		remote "sync" >/dev/null 2>&1 || true
	fi
	reboot_and_wait "$ws"
	log "done. Collect results with: ./scripts/boot-profile.sh collect $IP"
}

cmd_collect() {
	local ws
	ws="$(workspace)"
	mkdir -p "$ws"
	log "pulling boot-profile.log from $IP..."
	if ! curl -s -u root: "ftp://$IP/boot-profile.log" -o "$ws/boot-profile.log"; then
		die "could not fetch boot-profile.log"
	fi
	if [ ! -s "$ws/boot-profile.log" ]; then
		die "boot-profile.log is empty - the device was not booted with an instrumented initramfs (run inject)"
	fi
	curl -s -u root: "ftp://$IP/boot.log" -o "$ws/boot.log" || true
	generate_report "$ws" "$ws/boot-profile.log"
	if curl -s -u root: "ftp://$IP/boot-profiler.trace" -o "$ws/boot-profiler.trace"; then
		log "fetched boot-profiler.trace ($(wc -l <"$ws/boot-profiler.trace") lines)"
	fi
}

cmd_restore() {
	local ws stock
	ws="$(workspace)"
	mkdir -p "$ws"
	stock="$(fetch_stock "$ws")"
	log "extracting stock initramfs..."
	extract_stock_initramfs "$ws" "$stock"
	initramfs="$(repack_initramfs "$ws")"
	if [ "$OTA" -eq 1 ]; then
		cp "$initramfs" "$ws/stage/.minime/initramfs"
		local triple_str
		triple_str="$(triple)"
		local pkg="$ws/minime-${triple_str}-stock.tar.xz"
		(
			cd "$ws/stage" &&
				tar -cf - . | xz -T0 -9 >"$pkg"
		)
		log "delivering stock OTA via update-device.sh..."
		"$SCRIPTS/update-device.sh" "$pkg" "$IP"
	else
		log "uploading stock initramfs over FTP..."
		curl -s -S -u root: -T "$initramfs" "ftp://$IP/.minime/initramfs"
	fi
	remote "rm -f /mnt/sdcard/boot-profile.log /mnt/sdcard/boot-profiler.sh /mnt/sdcard/.boot-profiler-debug /mnt/sdcard/boot-profiler.trace; sync; reboot" >/dev/null 2>&1 || true
	log "rebooting with stock initramfs (profiler removed). Verify with: just check-version $OS $BOARD $UI"
}

print_help() {
	cat <<EOF
Usage: ./scripts/boot-profile.sh <command> [options]

Profiles the non-first boot on a live device without rebuilding an image.

Commands:
  baseline [ip]              Parse the last boot from the existing
                             /mnt/sdcard/boot.log (non-invasive, no reboot).
  inject [os board ui] [ip]  Instrument the stock testing initramfs with the
                             on-device observer, push it over FTP (or OTA with
                             --ota), and reboot the device.
  collect [ip]               Pull boot-profile.log and print the boot timeline,
                             phase durations, wifi handshake timing and top gaps.
  restore [os board ui] [ip] Push back the stock initramfs and reboot (removes
                             the profiler from the device).
  help                       Show this help.

Options:
  --ota                      Deliver via a rebuilt OTA package instead of a
                             direct initramfs FTP upload.
  --debug                    Run the observer under sh -x and leave the trace
                             at /mnt/sdcard/boot-profiler.trace (fetched by
                             collect). Debugging aid for the observer itself.

Defaults: os=alpine board=h700 ui=minui; IP from target_ip= in deploy.cfg.
Artifacts and cached stock OTA live under downloads/boot-profile/ (gitignored).
EOF
}

# --------------------------------------------------------------------------
CMD="${1:-}"
[ $# -gt 0 ] && shift
case "$CMD" in
baseline)
	parse_args "$@"
	cmd_baseline
	;;
inject)
	parse_args "$@"
	cmd_inject
	;;
collect)
	parse_args "$@"
	cmd_collect
	;;
restore)
	parse_args "$@"
	cmd_restore
	;;
help | --help | -h | "")
	print_help
	;;
*)
	print_help >&2
	exit 1
	;;
esac
