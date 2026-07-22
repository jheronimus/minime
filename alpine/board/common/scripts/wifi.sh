#!/bin/sh
# shellcheck shell=sh
# wifi.sh: connect configured Wi-Fi networks on Minime.
# Called by both the Alpine OpenRC 'wifi' service and the Buildroot S45wifi wrapper.
# Interface: wifi.sh {start|stop|reload|restart}

set -eu

wifi_interface="wlan0"
wpa_supplicant_state_dir="/tmp"
wpa_supplicant_config_file="${wpa_supplicant_state_dir}/wpa_supplicant.conf"
wpa_supplicant_seed_dir="/mnt/sdcard/.minime/config/wpa_supplicant"
wifi_config_file="/mnt/sdcard/.minime/config/wifi.cfg"
udhcpc_pidfile="/run/udhcpc.${wifi_interface}.pid"
udhcpc_logfile="/run/udhcpc.${wifi_interface}.log"
diagnostic_logfile="/tmp/wifi.diagnostics"

wpa_cli_wait_seconds=30
station_connect_wait_seconds=40
ipv4_wait_seconds=20
wifi_driver_wait_seconds=5

# Initialize base wpa_supplicant config with control interface
init_wpa_supplicant_conf() {
	mkdir -p "${wpa_supplicant_state_dir}"
	chmod 755 "${wpa_supplicant_state_dir}" 2>/dev/null || true
	{
		printf '%s\n' 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel'
		printf '%s\n' 'update_config=1'
		printf '%s\n' ''
	} > "${wpa_supplicant_config_file}"
	chmod 600 "${wpa_supplicant_config_file}" 2>/dev/null || true
}

# Append pre-configured wpa_supplicant profile snippets from SD card directory
seed_wpa_profiles() {
	[ -d "${wpa_supplicant_seed_dir}" ] || return 0
	for profile_path in "${wpa_supplicant_seed_dir}"/*.conf; do
		[ -f "${profile_path}" ] || continue
		cat "${profile_path}" >> "${wpa_supplicant_config_file}"
		printf '\n' >> "${wpa_supplicant_config_file}"
	done
}

# Parse wifi.cfg key-value pairs and append Wi-Fi profiles to wpa_supplicant config
load_wifi_cfg_profiles() {
	[ -f "${wifi_config_file}" ] || return 0
	ssid=""
	psk=""

	while IFS='=' read -r key val || [ -n "$key" ]; do
		[ -n "$key" ] || continue
		key=$(printf '%s' "$key" | tr -d '\r')
		val=$(printf '%s' "$val" | tr -d '\r')
		case "$key" in
			\#*) continue ;;
			SSID)
				if [ -n "$ssid" ]; then
					{
						printf 'network={\n\tssid="%s"\n' "$ssid"
						if [ -n "$psk" ]; then printf '\tpsk="%s"\n' "$psk"; else printf '\tkey_mgmt=NONE\n'; fi
						printf '}\n\n'
					} >> "${wpa_supplicant_config_file}"
					psk=""
				fi
				ssid="$val"
				;;
			Passphrase) psk="$val" ;;
		esac
	done < "${wifi_config_file}"

	if [ -n "$ssid" ]; then
		{
			printf 'network={\n\tssid="%s"\n' "$ssid"
			if [ -n "$psk" ]; then printf '\tpsk="%s"\n' "$psk"; else printf '\tkey_mgmt=NONE\n'; fi
			printf '}\n\n'
		} >> "${wpa_supplicant_config_file}"
	fi
}

# Unblock rfkill and wait for network interface to appear
prepare_wifi_interface() {
	i=0
	if command -v rfkill >/dev/null 2>&1; then
		rfkill unblock wifi >/dev/null 2>&1 || true
	fi
	while [ "${i}" -lt "${wifi_driver_wait_seconds}" ]; do
		if ip link show "${wifi_interface}" >/dev/null 2>&1; then
			ip link set "${wifi_interface}" up >/dev/null 2>&1 || true
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

# Poll wpa_cli until wpa_supplicant daemon responds
wait_for_wpa_supplicant_ready() {
	i=0
	while [ "${i}" -lt "${wpa_cli_wait_seconds}" ]; do
		if pidof wpa_supplicant >/dev/null 2>&1 &&
			wpa_cli -i "${wifi_interface}" ping >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

# Poll wpa_cli status until WPA authentication completes or times out
wait_for_wpa_handshake() {
	i=0
	while [ "${i}" -lt "${station_connect_wait_seconds}" ]; do
		if wpa_cli -i "${wifi_interface}" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

# Poll interface until an IPv4 address is assigned
wait_for_ipv4_address() {
	i=0
	while [ "${i}" -lt "${ipv4_wait_seconds}" ]; do
		if ip -4 addr show "${wifi_interface}" 2>/dev/null | grep -q "inet "; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

# Terminate running udhcpc DHCP client instances
stop_dhcp_client() {
	if [ -f "${udhcpc_pidfile}" ]; then
		kill "$(cat "${udhcpc_pidfile}")" >/dev/null 2>&1 || true
	fi
	# Kill any stray udhcpc processes for this interface
	for pid in $(pidof udhcpc 2>/dev/null); do
		tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null |
			grep -q -- "-i ${wifi_interface}" && kill "${pid}" 2>/dev/null || true
	done
	rm -f "${udhcpc_pidfile}"
}

# Launch background udhcpc client for IPv4 address assignment
start_dhcp_client() {
	stop_dhcp_client
	: > "${udhcpc_logfile}"
	udhcpc -b -R -x hostname:"$(hostname)" -F "$(hostname)" \
		-O search -O staticroutes \
		-p "${udhcpc_pidfile}" \
		-i "${wifi_interface}" \
		-s /usr/share/udhcpc/default.script \
		>> "${udhcpc_logfile}" 2>&1
}

# Async worker: brings up interface, daemon, connection, and DHCP
start_background() {
	has_profiles="$1"
	exec >/dev/null 2>&1

	if ! prepare_wifi_interface; then
		log_failure_diagnostics "missing-${wifi_interface}"
		return 1
	fi

	mkdir -p /var/run/wpa_supplicant
	start-stop-daemon -S -q -b -m \
		-p /var/run/wpa_supplicant.pid \
		-x /usr/sbin/wpa_supplicant -- \
		-i"${wifi_interface}" -c"${wpa_supplicant_config_file}"

	if ! wait_for_wpa_supplicant_ready; then
		log_failure_diagnostics "wpa_supplicant-not-ready"
		return 1
	fi

	wpa_cli -i "${wifi_interface}" reconfigure >/dev/null 2>&1 || true

	if [ "$has_profiles" -eq 0 ]; then
		return 0
	fi

	if ! wait_for_wpa_handshake; then
		log_failure_diagnostics "station-connect-timeout"
		return 1
	fi

	if wait_for_ipv4_address; then
		logger -t wifi "connection established (pre-DHCP)" 2>/dev/null || true
		return 0
	fi

	start_dhcp_client
	if ! wait_for_ipv4_address; then
		log_failure_diagnostics "ipv4-timeout"
		return 1
	fi

	logger -t wifi "connection established with IP" 2>/dev/null || true
	if [ -d /mnt/sdcard ]; then
		printf '[WIFI %s] Connection established with IP\n' \
			"$(date -u +'%T' 2>/dev/null || true)" >> /mnt/sdcard/boot.log 2>/dev/null || true
		sync 2>/dev/null || true
	fi
	return 0
}

# Non-blocking boot entrypoint: prepares config and forks background worker
start() {
	printf "Starting wifi: "
	init_wpa_supplicant_conf
	load_wifi_cfg_profiles
	seed_wpa_profiles

	has_profiles=0
	if grep -q '^network={' "${wpa_supplicant_config_file}" 2>/dev/null; then
		has_profiles=1
	fi

	start_background "${has_profiles}" &
	echo "OK (background)"
	return 0
}

# Stop Wi-Fi connection, DHCP client, and wpa_supplicant daemon
stop() {
	printf "Stopping wifi: "
	stop_dhcp_client
	if [ -f "/var/run/wpa_supplicant.pid" ]; then
		kill "$(cat "/var/run/wpa_supplicant.pid")" >/dev/null 2>&1 || true
		rm -f "/var/run/wpa_supplicant.pid"
	fi
	ip link set "${wifi_interface}" down >/dev/null 2>&1 || true
	echo "OK"
}

# Re-read Wi-Fi configurations and trigger wpa_supplicant reconfiguration
reload() {
	printf "Reloading wifi: "
	init_wpa_supplicant_conf
	load_wifi_cfg_profiles
	seed_wpa_profiles

	if ! wpa_cli -i "${wifi_interface}" ping >/dev/null 2>&1; then
		echo "starting"
		start
		return $?
	fi

	if ! wpa_cli -i "${wifi_interface}" reconfigure >/dev/null 2>&1; then
		echo "FAIL"
		return 1
	fi
	wpa_cli -i "${wifi_interface}" reassociate >/dev/null 2>&1 || true
	start_dhcp_client
	echo "OK"
}

# Dump interface/SDIO state to diagnostic log on connection failure
log_failure_diagnostics() {
	reason="$1"
	{
		printf '%s\n' "reason=${reason}"
		printf '%s ' "/sys/class/net/${wifi_interface}:"
		if [ -e "/sys/class/net/${wifi_interface}" ]; then
			printf '%s\n' "present"
			ip link show "${wifi_interface}" 2>&1 || true
		else
			printf '%s\n' "missing"
		fi
		printf '%s\n' "/sys/bus/sdio/devices:"
		ls -la /sys/bus/sdio/devices 2>&1 || true
		printf '%s\n' "wpa_cli -i ${wifi_interface} status:"
		if command -v wpa_cli >/dev/null 2>&1; then
			wpa_cli -i "${wifi_interface}" status 2>&1 || true
		else
			printf '%s\n' "wpa_cli missing"
		fi
	} >> "${diagnostic_logfile}"
	if [ -d /mnt/sdcard ]; then
		cp -f "${diagnostic_logfile}" /mnt/sdcard/wifi.diagnostics 2>/dev/null || true
		printf '[WIFI %s] startup failed: %s; diagnostics in /mnt/sdcard/wifi.diagnostics\n' \
			"$(date -u +'%T' 2>/dev/null || true)" "${reason}" >> /mnt/sdcard/boot.log 2>/dev/null || true
		sync 2>/dev/null || true
	fi
	logger -t wifi "startup failed: ${reason}; diagnostics in ${diagnostic_logfile}" 2>/dev/null || true
	echo "wifi: startup failed: ${reason}" >&2
}

case "${1:-}" in
	start)   start ;;
	stop)    stop ;;
	reload)  reload ;;
	restart) stop; sleep 1; start ;;
	*) echo "Usage: $0 {start|stop|reload|restart}" >&2; exit 1 ;;
esac
