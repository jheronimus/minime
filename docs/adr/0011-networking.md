# Networking & Wireless Services

## Problem
Headless handheld development and local wireless gaming require zero-configuration network connectivity, automatic reconnection, and passwordless developer access.

## Solution
Use `wpa_supplicant` for wireless connections (synced from `/mnt/sdcard/wifi.cfg`), `udhcpc` for automatic DHCP lease management, `mdnsd` for zero-configuration `.local` mDNS hostname resolution (`minime.local`), and passwordless Dropbear SSH and FTP for developer tooling.

## Examples
- Wi-Fi OpenRC service: `packages/components/boards/common/overlay/etc/init.d/wifi`
- SSH OpenRC service: `packages/components/boards/common/overlay/etc/init.d/dropbear`

## See Also
- Network services: [`packages/components/boards/common/overlay/etc/init.d/`](../../packages/components/boards/common/overlay/etc/init.d/)
