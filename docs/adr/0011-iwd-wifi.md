# 0011: Wi-Fi via iwd (replace wpa_supplicant)

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-06

---

## Context & Problem Statement

The wifi init service used `wpa_supplicant` + busybox `udhcpc`:
wpa_supplicant was backgrounded via `start-stop-daemon`, a hand-written
`wpa_supplicant.conf` was assembled from `/mnt/sdcard/.minime/config/wifi.cfg`
(`SSID=`/`Passphrase=`), and a slow background worker polled for the WPA
handshake and then launched `udhcpc`. This was the slowest boot step measured
in the boot profile (WPA handshake ~5.9s, DHCP another ~4s), and wpa_supplicant
did full scans by default.

## Decision

Transition Wi-Fi to **iwd (Internet Wireless Daemon)**:

- **Package**: `iwd` in the Alpine world (binary package, community repo) and
  `BR2_PACKAGE_IWD=y` in Buildroot (which selects `ell` + `dbus`).
  `BR2_PACKAGE_READLINE=y` enables the `iwctl` interactive tool.
- **Standalone, no wpa_supplicant, no udhcpc**: iwd performs 802.11 + WPA
  natively and, with `EnableNetworkConfiguration=true` in `/etc/iwd/main.conf`,
  provides its own DHCP client. `NameResolvingService=none` keeps DNS
  management out of scope for now (debug access is IP-based).
- **State on the FAT partition**: iwd persists known networks as `.psk`
  profiles in `$STATE_DIRECTORY`. Because `/var/lib` is on the read-only EROFS
  rootfs, the wifi service starts iwd with
  `STATE_DIRECTORY=/mnt/sdcard/.minime/config/iwd`. A seed dir
  (`.../iwd/seed/`) allows shipping pre-provisioned profiles. `wifi.cfg` is
  still honored: the service translates `SSID=`/`Passphrase=` into iwd `.psk`
  profile files (with `AutoConnect=true`) at start.
- **dbus**: iwd requires a system bus. The wifi service starts `dbus-daemon
  --system` idempotently (reusing the `/etc/machine-id` baked into the rootfs;
  no on-disk uuid write needed, unlike the old `dbus-uuidgen --ensure` which
  fails on a read-only rootfs). This also happens to fix the same latent bug
  in the bluetooth service.
- **Kernel crypto**: iwd's AES/CCMP + key handling needs crypto API options
  that were absent. Added to `tiny-base.config`: `CRYPTO_AES`, `CRYPTO_CMAC`,
  `CRYPTO_ECB`, `CRYPTO_HMAC`, `CRYPTO_SHA256`, `CRYPTO_SHA512`.
- **Connect wait preserved**: the service still waits for
  `iwctl station wlan0 show` to report `connected` before declaring success,
  so downstream services (`ui`, `ftpd`, `telnetd`, `dropbear`) see an IP.
- **Kernel `wifi` service keeps its name and runlevel slot** (boot runlevel),
  so no init ordering or OTA payload change is required beyond the image.

## Consequences

- **Faster boot**: iwd's `DisablePeriodicScan=true` and leaner stack should
  cut the WPA+DHCP portion of the boot profile (expected; to be re-measured
  on device).
- **wpa_supplicant and udhcpc are removed** from both targets. Any UI or
  contract that assumed `wpa_cli`/`wpa_supplicant.conf` no longer applies;
  Minime exposes wifi via `wifi.cfg` + the iwd state dir, both of which are
  stable.
- **Known networks persist on FAT** and survive rootfs/OTA updates.
- **dbus now always runs** when wifi is up (needed by iwd), which also makes
  bluetooth's dbus startup more robust.
- **Dropbear** (SSH) was added in the same change: binary in both targets,
  shared `/etc/init.d/dropbear` init script, **not enabled by default** (no
  runlevel entry; opt-in via `rc-update add dropbear default` and the
  `/mnt/sdcard/.minime/config/ssh/enabled` marker). Host keys live on the FAT
  partition.

---

## Reference

- Previous wifi service: `minime/boards/common/overlay/etc/init.d/wifi`
  (wpa_supplicant + udhcpc version).
- iwd storage/config dirs: `iwd.network(5)` — `$STATE_DIRECTORY` defaults to
  `/var/lib/iwd`, overridden per-daemon.
- Boot profile (pre-change): WPA handshake ~5.9s, DHCP ~4s.
- Related logging ADR: `docs/adr/0010-logging-and-diagnostics.md`.
