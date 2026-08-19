# ADR 0016: Passwordless Network Services During Development

* **Status**: Accepted (interim, for the active development/debugging stage)
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-07

---

## Context & Problem Statement

Minime is a firmware for open handheld devices under active development. The
primary remote-access paths (Wi-Fi, telnet, FTP) are used heavily for
on-device debugging, log collection, and CI verification. During this stage,
access speed and zero-friction win over security: a developer or an AI agent
must be able to reach a device and inspect/modify it without key or password
ceremony.

The question was whether the SSH server (dropbear) should follow this same
no-auth model or impose key-based authentication.

## Decision

All network services exposed by the init system are **passwordless** while the
project is in the heavy development/debugging stage. Specifically:

| Service | Port | Auth model | Implementation |
|---|---|---|---|
| `telnetd` | 23 | None | busybox `telnetd -l /usr/bin/autologin`; drops into `/bin/sh -l` |
| `ftpd` | 21 | Anonymous | `tcpsvd ... /usr/sbin/ftpd -A -w /mnt/sdcard` (read/write of the whole SD card) |
| `dropbear` (SSH) | 22 | Blank-password root | `dropbear -B` with an **empty root password** baked into the rootfs |
| `wifi` (iwd) | — | WPA2-PSK only | iwd authenticates to the AP via `wifi.cfg`; no device-side auth; also starts `ntpd` (time sync) once connected |
| `logger` | — | — | persists kernel + syslog per boot; not a login service |

### Implementation details

- **Empty root password**: both targets bake `root::` (empty) into
  `/etc/shadow`:
  - Alpine: `passwd -d root` during `assemble_rootfs` in `build.sh`.
  - Buildroot: `BR2_TARGET_GENERIC_ROOT_PASSWD=""`.
- **dropbear**: runs with `-B` (allow blank-password logins) and a host key
  persisted on the FAT partition (`/mnt/sdcard/.minime/config/ssh/`), so
  `ssh <host>` connects as root without prompting — behaviourally identical
  to `telnet <host>`.
- **SSH is enabled by default**: the `dropbear` service is in the `boot`
  runlevel alongside telnet/FTP. To disable it on a device, touch
  `/mnt/sdcard/.minime/config/ssh/disabled` and reboot (or
  `rc-service dropbear stop`).

### Rationale

- **Development velocity**: agents and developers need immediate access; a key
  or password round-trip on every device slows down the on-device verification
  loop mandated by the repo's `live-test` workflow.
- **Consistency**: telnet, FTP, and Wi-Fi-to-AP were already passwordless.
  Adding key-auth only to SSH would be inconsistent and confusing.
- **Hardware context**: the services only run on a local Wi-Fi LAN, on
  developer-owned devices, behind a WPA2-PSK access point.

## Consequences

- **Security exposure**: any device on the same LAN (or anyone with the Wi-Fi
  PSK) can reach root over telnet/FTP/SSH with no credentials. This is
  **unacceptable for end-user firmware** and must not ship in a release.
- **Explicit re-evaluation point**: before the codebase matures to a
  "stable/user-facing" state (per the project goals), this policy must be
  revisited:
  - Replace autologin telnet with authenticated access or remove it.
  - Require key-based SSH (drop `-B`, ship an `authorized_keys` flow).
  - Restrict FTP to read-only or remove it.
  - Consider a per-device `enabled` gate for all remote services.
- A follow-up ADR should supersede this one when the security model is
  tightened.

---

## Reference

- Init services: `packages/components/boards/common/overlay/etc/init.d/{telnetd,ftpd,dropbear,wifi}`.
- Empty-password build steps: `packages/components/alpine/scripts/build.sh`,
  `packages/components/buildroot/external/configs/common.config`.
- Related: `docs/adr/0007-logging-and-diagnostics.md` (log capture over these
  services), `docs/adr/0015-iwd-wifi.md` (Wi-Fi stack).
