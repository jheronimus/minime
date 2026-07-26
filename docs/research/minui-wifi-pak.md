# MinUI WiFi Implementation Research

**Source**: [josegonzalez/minui-wifi-pak](https://github.com/josegonzalez/minui-wifi-pak) (53 stars, actively maintained)  
**Platforms**: miyoomini, my282 (Miyoo A30), my355 (Miyoo Flip), tg5040 (Trimui Brick/Smart Pro), rg35xxplus (RG-35XX Plus/H/SP, RG-34XX)

## Architecture Overview

MinUI does NOT have built-in WiFi support. WiFi is implemented as an **optional "pak"** (`Wifi.pak`) that users install to `/Tools/$PLATFORM/Wifi.pak/`. The pak consists of:

```
Wifi.pak/
├── launch.sh              # Main UI entry point
├── bin/
│   ├── service-on         # Start wpa_supplicant + DHCP
│   ├── service-off        # Stop wpa_supplicant + DHCP
│   ├── on-boot            # Auto-start on boot (calls service-on)
│   ├── wifi-enabled       # Check if WiFi is currently active
│   ├── arm/               # Static binaries (jq, wpa_supplicant, etc.)
│   └── $PLATFORM/         # Platform-specific binaries (minui-list, minui-keyboard, minui-presenter)
├── res/
│   ├── wpa_supplicant.conf.tmpl         # Base wpa_supplicant template
│   ├── wpa_supplicant.conf.miyoomini.tmpl
│   ├── wpa_supplicant.conf.my282.tmpl
│   ├── wpa_supplicant.conf.my355.tmpl
│   ├── netplan.yaml.tmpl                # For rg35xxplus (uses systemd-networkd)
│   └── settings.json / settings.enabled.json / settings.connected.json / settings.no-ip.json
└── lib/
    └── $PLATFORM/         # Platform-specific shared libraries
```

## Key Scripts

### `launch.sh` - Main WiFi UI

The main script provides a settings UI for managing WiFi. Key patterns:

- **Logging**: All output redirected to `$LOGS_PATH/$PAK_NAME.txt` via `exec >>` and `exec 2>&1`
- **Architecture detection**: `uname -m | grep -q '64'` → arm64 vs arm
- **PATH setup**: Prepends pak's own bin directories to PATH
- **Platform override**: Handles `tg3040` → `tg5040` and `miyoomini` → `miyoominiplus` detection
- **Stay awake**: Writes `1` to `/tmp/stay_awake` to prevent sleep during WiFi operations

### `service-on` - Start WiFi

Platform-specific startup sequence:

**Common pattern across platforms:**
1. Kill existing `wpa_supplicant` and `udhcpc`
2. Bring up `wlan0` interface with `ifconfig wlan0 up`
3. Start `wpa_supplicant` in background (`-B` flag)
4. Start `udhcpc` for DHCP
5. Check `pgrep wpa_supplicant` to verify it started

**Platform-specific differences:**

| Platform | wpa_supplicant | DHCP | Special |
|----------|---------------|------|---------|
| miyoomini | `/customer/app/wpa_supplicant -B -D nl80211 -iwlan0 -c /appconfigs/wpa_supplicant.conf` | `udhcpc -i wlan0 -s /etc/init.d/udhcpc.script &` | Loads `8188fu.ko` kernel module, uses `axp_test wifion` for power |
| tg5040 | `wpa_supplicant -B -D nl80211 -iwlan0 -c /etc/wifi/wpa_supplicant.conf -O /etc/wifi/sockets` | `udhcpc -i wlan0 -n &` | Handles stale socket cleanup |
| my282 | `/etc/init.d/wpa_supplicant start` (init.d) | `(udhcpc -i wlan0 -q & )&` | Uses init.d script |
| my355 | `wpa_supplicant -B -D nl80211 -iwlan0 -c /userdata/cfg/wpa_supplicant.conf` | `(udhcpc -i wlan0 -q & )&` | Uses `wpa_cli` for status |
| rg35xxplus | `systemctl start wpa_supplicant` | `systemctl start systemd-networkd` + `netplan apply` | Uses systemd, netplan |

### `service-off` - Stop WiFi

1. Update `system.json` to set `wifi: 0`
2. Try init.d, systemctl, then `killall -9 wpa_supplicant`
3. Check `/sys/class/net/wlan0/flags` for `0x1003` before bringing interface down
4. `rfkill block wifi` if available
5. Reset wpa_supplicant.conf to template
6. For rg35xxplus: remove netplan config, apply, stop systemd-networkd

### `wifi-enabled` - Check WiFi Status

Returns 0 (success) only if ALL conditions met:
1. `system.json` has `wifi: 1`
2. `rfkill` not blocked
3. `wpa_supplicant` is running (`pgrep wpa_supplicant`)
4. Interface is up (`/sys/class/net/wlan0/flags` == `0x1003`)

### `on-boot` - Auto-start

Simply calls `service-on &` (backgrounded).

## WiFi Status Detection

### Interface Check
```sh
# Check if interface is up
STATUS=$(cat /sys/class/net/wlan0/operstate)
# or
[ "$(cat /sys/class/net/wlan0/flags 2>/dev/null)" = "0x1003" ]
```

### SSID and IP Retrieval
```sh
# Platform-specific (my355 uses wpa_cli)
if [ "$PLATFORM" = "my355" ]; then
    ssid="$(wpa_cli -i wlan0 status | grep ssid= | grep -v bssid= | cut -d'=' -f2)"
    ip_address="$(wpa_cli -i wlan0 status | grep ip_address= | cut -d'=' -f2)"
else
    ssid="$(iw dev wlan0 link | grep SSID: | cut -d':' -f2- | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')"
    ip_address="$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)"
fi
```

### Connection Wait Loop
```sh
DELAY=30
for i in $(seq 1 "$DELAY"); do
    STATUS=$(cat "/sys/class/net/wlan0/operstate")
    if [ "$STATUS" = "up" ]; then
        break
    fi
    sleep 1
done
```

## Credential Management

Credentials stored in `$SDCARD_PATH/wifi.txt` (root of SD card):
```
# Comments ignored
SSID_NAME:password
OPEN_NETWORK:
```

### Config Generation
```sh
# Generate wpa_supplicant.conf from template + wifi.txt
while read -r line; do
    ssid="$(echo "$line" | cut -d: -f1 | xargs)"
    psk="$(echo "$line" | cut -d: -f2- | xargs)"
    
    echo "network={"
    echo "    ssid=\"$ssid\""
    if [ -z "$psk" ]; then
        echo "    key_mgmt=NONE"
    else
        echo "    psk=\"$psk\""
    fi
    echo "}"
done < "$SDCARD_PATH/wifi.txt"
```

### Platform-Specific Config Paths
| Platform | wpa_supplicant.conf location |
|----------|------------------------------|
| miyoomini | `/etc/wifi/wpa_supplicant.conf` + `/appconfigs/wpa_supplicant.conf` |
| my282 | `/etc/wifi/wpa_supplicant.conf` + `/config/wpa_supplicant.conf` |
| my355 | `/userdata/cfg/wpa_supplicant.conf` |
| tg5040 | `/etc/wifi/wpa_supplicant.conf` |
| rg35xxplus | `/etc/wpa_supplicant/wpa_supplicant.conf` + `/etc/netplan/01-netcfg.yaml` |

## Error Handling Patterns

1. **Return codes**: Functions return 0/1, caller checks with `if ! command; then`
2. **Process verification**: `pgrep wpa_supplicant` after starting
3. **UI feedback**: `show_message "message" timeout_seconds` using `minui-presenter`
4. **Timeout loops**: 30-second loops with 1-second sleep for interface/connection
5. **Kill before start**: Always `killall` existing processes before starting new ones
6. **Socket cleanup** (tg5040): Checks log for stale socket, removes and restarts

## MinUI Main launch.sh Pattern (from original repo)

The MinUI launcher itself has NO WiFi code. It explicitly kills WiFi on startup:
```sh
# disable internet stuff
killall MtpDaemon
killall wpa_supplicant
killall udhcpc
rfkill block bluetooth
rfkill block wifi
```

WiFi is only active when the Wifi.pak is running. The `auto.sh` mechanism enables WiFi on boot:
```sh
# In auto.sh (managed by Wifi.pak)
test -f "$SDCARD_PATH/Tools/$PLATFORM/Wifi.pak/bin/on-boot" && "$SDCARD_PATH/Tools/$PLATFORM/Wifi.pak/bin/on-boot"
```

## Key Takeaways for Minime

1. **Modular design**: WiFi is a separate pak, not part of core launcher
2. **Per-platform paths**: Each platform has different config locations and binaries
3. **Simple wpa_supplicant**: No NetworkManager, just wpa_supplicant + udhcpc
4. **Credential file**: Simple `SSID:password` format, one per line
5. **Power management**: miyoomini needs `axp_test wifion/wifioff` for WiFi power
6. **Kernel modules**: Some platforms need to load WiFi driver module first
7. **System state**: Stored in `system.json` on each platform's config partition
8. **Boot integration**: Uses MinUI's `auto.sh` hook for start-on-boot feature
