# ROCKNIX WiFi Implementation Research

**Source:** https://github.com/ROCKNIX/distribution (branch: `next`)
**Date:** 2026-07-26

## Architecture Overview

ROCKNIX uses a **three-layer WiFi stack**:

1. **iwd** (wireless daemon) - handles 802.11 scanning, association, WPA
2. **NetworkManager** (with iwd backend) - handles connection profiles, DHCP, DNS
3. **wifictl** (custom script) - user-facing control interface

Key design decisions:
- iwd does NOT manage IP/DHCP (`EnableNetworkConfiguration=false`)
- NetworkManager owns all IP configuration; uses iwd as WiFi backend (`wifi.backend=iwd`)
- DHCP is internal to NetworkManager (`dhcp=internal`)
- DNS uses systemd-resolved (`dns=systemd-resolved`)
- No wpa_supplicant anywhere in the stack

## File Locations

### Boot Autostart
- `projects/ROCKNIX/packages/rocknix/autostart/080-network` - WiFi enable/disable on boot
- `projects/ROCKNIX/packages/rocknix/autostart/099-networkservices` - starts daemons via systemd

### WiFi Control Script
- `projects/ROCKNIX/packages/rocknix/sources/scripts/wifictl` - main WiFi control script

### Service Configuration
- `projects/ROCKNIX/packages/network/networkmanager/package.mk` - NM build config
- `projects/ROCKNIX/packages/network/networkmanager/config/NetworkManager.conf` - NM runtime config
- `projects/ROCKNIX/packages/network/iwd/package.mk` - iwd build config
- `projects/ROCKNIX/packages/network/iwd/sources/main.conf` - iwd runtime config

---

## Script: `080-network` (Boot WiFi Init)

```sh
#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Minimal OS variable loading for performance
. /etc/profile.d/001-functions

tocon "Configuring network..."

if [ "$(get_setting wifi.enabled)" == "0" ] || [ "$1" == "disable" ]
then
  nohup wifictl disable &
elif [ "$(get_setting wifi.enabled)" == "1" ] || [ "$1" == "enable" ]
then
  nohup wifictl enable &
fi
```

**Pattern:**
- Reads persistent setting from `get_setting wifi.enabled`
- Runs `wifictl` in background via `nohup ... &`
- Supports CLI override (`$1 == "disable"` / `"enable"`)
- Minimal, fast boot script

---

## Script: `wifictl` (WiFi Control)

Full script (~150 lines). Key structure:

```sh
#!/bin/bash
. /etc/profile

NMCLI="$(command -v nmcli 2>/dev/null)"

IWD_AP_CFG_DIR="/storage/.cache/iwd/ap"
WIFI_TYPE=$(get_setting wifi.adhoc.enabled)
NETWORK_ADDRESS="192.168.80"
ADHOC_CLIENT_ID=$(get_setting wifi.adhoc.id)
WIFI_DEV="$(ls /sys/class/net | grep -m1 ^wlan)"
DEFAULT_CHAN="6"

# Early exit guards
[ -z "${WIFI_DEV}" ] && exit 0
[ ! -d "/sys/class/net/${WIFI_DEV}" ] && exit 0
[ -z "${NMCLI}" ] && exit 0

# Read settings (with defaults)
SSID="${2:-$(get_setting wifi.ssid 2>/dev/null)}"
PSK="${3:-$(get_setting wifi.key 2>/dev/null)}"
COUNTRY="${4:-$(get_setting wifi.country | tr -d '[:space:]' 2>/dev/null)}"
```

### Key Functions

**`wait_for_wifi()`** - Waits for iwd to be ready:
```sh
wait_for_wifi() {
  for i in $(seq 1 5); do
    iwctl device list | grep -q "${WIFI_DEV}" && break
    sleep 1
  done
  [ -n "${COUNTRY}" ] && iw reg set "${COUNTRY}"
}
```

**`connect_wifi()`** - Connects via NetworkManager:
```sh
connect_wifi() {
  wait_for_wifi
  # Wait for NM device to be ready (up to 10 seconds)
  for i in $(seq 1 10); do
    "${NMCLI}" -t -f DEVICE,STATE dev status 2>/dev/null | grep -q "^${WIFI_DEV}:disconnected" && break
    "${NMCLI}" -t -f DEVICE,STATE dev status 2>/dev/null | grep -q "^${WIFI_DEV}:connected" && return 0
    sleep 1
  done
  "${NMCLI}" dev wifi rescan ifname "${WIFI_DEV}" 2>/dev/null
  sleep 2
  # Clean stale profiles to avoid NM connection-update failures
  "${NMCLI}" connection delete id "${SSID}" >/dev/null 2>&1 || true
  if [ -n "${PSK}" ]; then
    "${NMCLI}" -w 90 device wifi connect "${SSID}" password "${PSK}" ifname "${WIFI_DEV}" >/dev/null 2>&1
  else
    "${NMCLI}" -w 90 device wifi connect "${SSID}" ifname "${WIFI_DEV}" >/dev/null 2>&1
  fi
}
```

**`create_adhoc()`** - Creates WiFi AP for netplay:
```sh
create_adhoc() {
  wait_for_wifi
  "${NMCLI}" device set "${WIFI_DEV}" managed no >/dev/null 2>&1
  # Creates iwd AP profile file
  mkdir -p "${IWD_AP_CFG_DIR}"
  cat <<EOF >"${IWD_AP_CFG_DIR}/${SSID}.ap"
[General]
Channel=${ADHOC_CHAN}
DisableHT=true

[Security]
Passphrase=${PSK}

[IPv4]
Address=${NETWORK_ADDRESS}.${ADHOC_CLIENT_ID}
Netmask=255.255.255.0
Gateway=${NETWORK_ADDRESS}.${ADHOC_CLIENT_ID}
EOF
  iwctl device ${WIFI_DEV} set-property Mode ap
  iwctl ap ${WIFI_DEV} start-profile "${SSID}" 2>/dev/null
}
```

**Main dispatch (case statement):**
```sh
case "${1}" in
  enable)     rfkill unblock wifi ;;
  disable)    rfkill block wifi ;;
  connect)    # adhoc or normal WiFi connect
  disconnect) # NM or iwd AP disconnect
  reconnect)  # disconnect + connect
  list)       # scan + list SSIDs
  channels)   # list available channels
  has_ap_mode) # check AP support
  scan)       # trigger rescan
  scanlist)   # rescan + list
esac
```

---

## Configuration Files

### NetworkManager.conf
```ini
[main]
auth-polkit=false
plugins=keyfile
dhcp=internal
dns=systemd-resolved

[device]
wifi.backend=iwd

[keyfile]
path=/storage/.config/NetworkManager/system-connections
unmanaged-devices=interface-name:gadget;interface-name:usb0;interface-name:usbnet;interface-name:rndis0
```

### iwd main.conf
```ini
# IP/DHCP is handled by NetworkManager; iwd only does 802.11 + WPA.
[General]
EnableNetworkConfiguration=false
ControlPortOverNL80211=true

[Network]
RoutePriorityOffset=200
NameResolvingService=systemd
EnableIPv6=true

[Scan]
MaximumPeriodicScanInterval=30
```

---

## Notable Patterns

### 1. Background/Synchronous Split
- Boot init (`080-network`) runs `wifictl` in background (`nohup ... &`)
- `wifictl connect` runs synchronously (blocking) when called from UI
- `wifictl enable/disable` are instant (just rfkill)
- NM connection attempts have explicit timeouts (`-w 90` for connect, `-w 15` for scan)

### 2. Interface Detection
- Detects WiFi interface by scanning `/sys/class/net` for `wlan*`
- Uses `grep -m1 ^wlan` to get first matching interface
- Early exit if no interface found: `[ -z "${WIFI_DEV}" ] && exit 0`

### 3. Error Handling
- All NM commands redirect to `/dev/null` (silent failure)
- `wait_for_wifi()` polls up to 5 times with 1-second sleep
- `connect_wifi()` waits up to 10 seconds for device readiness
- Stale NM profiles are proactively deleted before connect
- `|| true` on cleanup commands to prevent error propagation

### 4. Ad-hoc/netplay AP Mode
- Unmanages device from NM (`nmcli device set managed no`)
- Creates iwd AP profile file directly
- Uses `iwctl ap` to start/stop AP
- Re-manages device on cleanup

### 5. Settings Integration
- All settings read via `get_setting` function (persistent config)
- Settings keys: `wifi.enabled`, `wifi.ssid`, `wifi.key`, `wifi.country`, `wifi.adhoc.*`

### 6. Service Management
- iwd and NetworkManager are systemd services (enabled via `enable_service`)
- connman is NOT used (ROCKNIX migrated away from it)
- iwd is built WITHOUT systemd service file (removed in post_makeinstall)
- NetworkManager uses `network-online.service` helper

### 7. Boot Sequence
1. systemd starts `iwd.service` (wireless daemon)
2. systemd starts `NetworkManager.service` (after dbus)
3. `rocknix-autostart.service` runs autostart scripts in order:
   - `080-network` → `wifictl enable` (background)
   - `099-networkservices` → starts other daemons
