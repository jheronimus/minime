# 0018: mDNS Self-Announcement (`minime.local`)

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

Remote tooling (`just remote`, `just deploy`, the on-device updater of
ADR 0017) needs to reach the device by **name or IP**. IPs come from DHCP and
change; hardcoding them in `deploy.cfg` (`target_ip=...`) is fragile and
breaks the moment more than one device is on the network.

A per-SoC naming scheme was considered (`minime.rk3566`, `minime.h700`,
`minime.rk3326`), but **mDNS hostnames are single-label** under `.local`
(RFC 6762) — `minime.rk3566.local` would register only `minime` as the
hostname and collide with every other Minime. The SoC is also no longer
needed in the name, because the device identifies itself during updates
(ADR 0017). The remaining question is therefore just: how does every Minime
announce a stable, unique, resolvable name?

## Decision

Every Minime announces **`minime.local`** over mDNS. A second device that
also claims it gets auto-renamed to `minime-2.local` via RFC 6762 probing and
conflict resolution, so both stay reachable.

### 1. Daemon: mdnsd (troglobit) on both targets

[mdnsd](https://github.com/troglobit/mdnsd) is a dependency-free
(no D-Bus), ~23 KiB mDNS/DNS-SD responder. It publishes A/AAAA records for
the advertised hostname, tracks interfaces over netlink in real time (it can
start before Wi-Fi connects), and implements RFC 6762 conflict probing with
`-2`-style auto-rename. Chosen over avahi (D-Bus, heavier) and over
mDNSResponder.

- **Buildroot**: `BR2_PACKAGE_MDNSD=y` was already in
  [common.config](../../minime/targets/buildroot/external/configs/common.config)
  but shipped no init service — its SysV `S50mdnsd` is removed by
  `post-build.sh`. This ADR wires it up with the shared service below.
- **Alpine**: built as a local aport
  [aports/mdnsd/APKBUILD](../../minime/targets/alpine/aports/mdnsd/APKBUILD)
  from the upstream release tarball, pinned to **v1.1** (the same version
  Buildroot uses), and added to `world-common` + the `build.sh` package loop.

### 2. Shared init service

[init.d/mdns](../../minime/boards/common/overlay/etc/init.d/mdns) (boot
runlevel) runs `mdnsd -n -s -H minime`:

- `-n` keeps mdnsd in the foreground so `start-stop-daemon` tracks the pid
  correctly (mdnsd daemonizes by default otherwise).
- `-s` routes logs to syslog (captured by the `logger` service, ADR 0010).
- `-H minime` fixes the advertised hostname, independent of the OS hostname
  service.
- The pidfile is managed by `start-stop-daemon --make-pidfile`; mdnsd 1.1 has
  no `-p` flag (added in 1.2).
- `depend()` is `need localmount modules` only — no `after wifi`, since
  netlink tracking handles the interface appearing whenever Wi-Fi connects
  (and avoids waiting on the wifi service's 40 s connect timeout).

### 3. Service records

[`/etc/mdns.d/`](../../minime/boards/common/overlay/etc/mdns.d/) ships four
DNS-SD records — `_minime._tcp` (custom discovery type) plus `_telnet._tcp`,
`_ftp._tcp`, `_ssh._tcp` for the remote-access daemons (ADR 0013). These
records are what make mdnsd register the `minime.local` A/AAAA records in the
first place, and make devices browseable in `avahi-browse`/Bonjour.

### 4. Client side

macOS resolves `.local` natively via Bonjour in `getaddrinfo`, `curl`, and
python sockets, so `target_ip=minime.local` in `deploy.cfg` works with all
existing scripts unchanged. Windows behaves similarly; Linux dev hosts need
an mDNS-aware resolver (avahi + nss-mdns).

## Consequences

- Stable, DHCP-independent device reachability for `just remote` / the
  on-device updater, no SoC-specific names needed.
- `.local` resolution is client-dependent: macOS/Windows work out of the box;
  Linux needs nss-mdns.
- Two same-name devices resolve to `minime.local` / `minime-2.local` — which
  device gets which is not predictable.
- mDNS is link-local and unauthenticated; it exposes only a hostname and
  service/port presence, consistent with the development-phase security
  posture of ADR 0013.
- Alpine's mdnsd builds from source in CI (Buildroot's was already building).

## Reference

- Init service: `minime/boards/common/overlay/etc/init.d/mdns`,
  `minime/boards/common/overlay/etc/runlevels/boot/mdns`,
  `minime/boards/common/overlay/etc/mdns.d/*.service`.
- Build integration: `minime/targets/alpine/aports/mdnsd/APKBUILD`,
  `minime/targets/alpine/configs/world-common`, `minime/targets/alpine/scripts/build.sh`,
  `minime/targets/buildroot/external/configs/common.config`.
- Client docs: `deploy_sample.cfg`, `.agents/skills/live-test/SKILL.md`.
- Related: `docs/adr/0017-on-device-ota-update-tool.md` (the update path the
  name serves), `docs/adr/0013-network-services-passwordless.md`.
