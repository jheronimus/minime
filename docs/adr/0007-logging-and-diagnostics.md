# ADR 0007: Persistent Per-Boot Logging and On-Demand Diagnostics

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-06

---

## Context & Problem Statement

Minime has no coherent logging story. Kernel messages live only in the volatile
RAM ring buffer (`dmesg`), which is wiped by the hard power-cycle used to recover
from a hang. Userspace daemon output (wpa_supplicant, bluetoothd, dbus, udhcpc,
ftpd, telnetd) is discarded entirely because no syslogd/klogd runs. The logs that
do exist are scattered: U-Boot writes `.minime/boot.log`, the initramfs and
init.d scripts append to a FAT-root `boot.log`, wifi failure dumps land in
`wifi.diagnostics`, and the UI stdout/stderr goes to a tmpfs `ui.log` that is
lost on reboot.

Debugging the intermittent shutdown hang (kernel `BUG: scheduling while atomic`
in `sun20i_pwm_apply`) repeatedly hit this wall: the messages right before a
hang were unrecoverable after a hard power-cycle, and userspace daemons logged
nothing at all.

Surveying Rocknix, muOS, and Knulli (Batocera lineage) confirmed the industry
patterns: muOS ships an on-demand "System Diagnostics" collector that bundles
`dmesg` + all logs + config into one timestamped archive; Rocknix keeps
`boot.log` plus per-launch stdout/stderr under `/var/log`; Knulli/Batocera keep
logs on the writable persistent partition. Kernel pstore was considered but
rejected: ramoops lives in reserved RAM, which a hard power-cycle clears, so it
cannot capture our specific crash class (see Consequences).

## Decision

### Layout

```
/mnt/sdcard/.minime/logs/
├── .seq                     # monotonic per-day counter state: "YYYYmmdd N"
├── current                  # boot-id pointer for the active boot, e.g. "20260806-3"
└── <boot-id>/               # e.g. 20260806-3
    ├── boot.log             # U-Boot stage markers + initramfs + init.d markers
    ├── kernel.log           # raw /dev/kmsg drain (boot log + live stream)
    └── syslog.log           # busybox syslogd catch-all (userspace daemons)
```

Boot-id = `YYYYmmdd-N`, where N is a per-day counter. The time-of-day component
is deliberately omitted because the device RTC wakes in the past and the
initramfs advances the clock to build time until NTP syncs, making `HHMMSS`
either wrong or identical across cold boots. The counter is stored in
`.minime/logs/.seq` as `DATE COUNTER`; on each boot the initramfs resets the
counter to 1 if the stored date differs from today, else increments it.

### Ownership

- **`.minime` is the firmware namespace**; `.system` is the UI payload
  namespace (assembled independently by `genassets.sh` + UI submodule forks).
  This change keeps that boundary: firmware and ui-service logs live under
  `.minime/logs/`, while UI-internal logs (MinUI's `minui.txt`, `keymon.txt`,
  `DIAG-*.txt`) remain under `.userdata/<platform>/logs/` where the UI itself
  writes them. No UI code changes are required.
- **Scope**: boot, kernel, and syslog — plus the ui-service stdout capture
  (family 1 and 2 from the design review). UI-internal logs (family 3) are out
  of scope.

### Boot flow

1. U-Boot writes stage markers to `.minime/boot.log` (unchanged; it cannot know
   a boot-id).
2. Initramfs, after mounting the FAT partition, fixing clock skew, and
   mounting the EROFS system, establishes the boot-id: reads/updates `.seq`,
   creates `logs/<boot-id>/`, **moves** U-Boot's `.minime/boot.log` and the
   root `boot.log` (containing early initramfs markers) into
   `logs/<boot-id>/boot.log`, and writes `logs/current`. Subsequent
   `[INITRAMFS]` markers append there.
3. `wifi`/`ui`/`traits` init.d services read `logs/current` and append their
   `[WIFI]/[UI]/[TRAITS]` markers into the same per-boot `boot.log` (via a
   shared helper installed alongside `device.sh`).
4. The `logger` OpenRC service (boot runlevel) starts:
   - a `/dev/kmsg` drain appending to `logs/<boot-id>/kernel.log`, syncing every
     3 seconds so a hard power-cycle loses at most ~3s of messages;
   - busybox `syslogd` writing to `logs/<boot-id>/syslog.log`;
   - a prune pass deleting per-boot dirs older than 7 days (FAT mtime).
5. On clean shutdown the service `stop()` appends the final `dmesg` tail to
   `kernel.log` and syncs.

### Why `/dev/kmsg`, not klogd

busybox klogd forwards kernel messages to syslog, but forwarding proved flaky in
on-device testing (kernel messages did not reliably land in the syslog file).
The raw `/dev/kmsg` drain is robust, non-destructive to other readers, and keeps
kernel log record sequence numbers and microsecond timestamps — strictly better
forensics for crash analysis. `kernel.log` is therefore independent of syslogd;
if syslogd wedges, the crash trace is still captured.

### On-demand diagnostics

A device-side `collect-diagnostics.sh` (installed alongside `device.sh`)
bundles, on demand:

- `logs/` (all per-boot dirs),
- live `dmesg` output,
- wifi diagnostics (if present),
- `.minime/traits`, `.minime/ui.env`, `.minime/config/*`,
- `.system/version.txt` and commit info,

into `minime-diagnostics-YYYYmmdd.tar.gz` at the FAT root. A host-side
`just get-logs` runs the collector over telnet (resolving the target IP from
`deploy.cfg` exactly like `remote-cmd.sh`), then pulls the archive over FTP
(the device already runs `ftpd` serving `/mnt/sdcard`) into `downloads/`.

## Consequences

- **Kernel crash forensics survive hard power-cycles**: the hang's last kernel
  messages are synced to FAT every 3s, so recovery is "power-cycle, read
  `logs/<boot-id>/kernel.log`".
- **Userspace daemons finally log**: wpa_supplicant, bluetoothd, dbus, udhcpc,
  ftpd, telnetd all land in `syslog.log` via syslogd.
- **Cross-boot comparison is possible**: per-boot dirs let us diff a crashing
  boot against earlier clean boots.
- **Log growth is bounded**: 7-day mtime prune caps total log footprint.
- **First-boot FAT expansion is safe**: the boot-id block runs after the
  clock-skew fix, which itself is after the EROFS mount — i.e. after the
  one-time DDR3-swap/probe/expand branches (each of which reboots). Those
  early branches keep writing the root `boot.log`, which is then adopted into
  the first normal boot's per-boot dir. The expand path stages the entire FAT
  (including any `logs/` and `.seq`) into tmpfs before the mkfs.vfat wipe and
  restores it afterwards, so boot-id state survives the one-time reformat.
- **OTA updates do not disturb logs**: `mkupdate.sh` only packs
  `.minime/{kernel,initramfs,system,devices,ui.env,manifest.json}` and
  `.system/`; `logs/` persists across updates.
- **Rejected: kernel pstore/ramoops** for crash capture. ramoops stores in
  reserved RAM, which is cleared by the hard power-cycle used to recover from a
  hang; a block backend on the SD was not worth the complexity at this stage.
  Revisit if we add a dedicated writable partition.
- **Rejected: UI-internal log relocation**. MinUI/Allium write their own logs
  under `.userdata/<platform>/logs/`; moving them would require patching UI
  code and break the UI contract, violating the minimal-UI-intrusion rule.

---

## Reference

- The hang under diagnosis: `BUG: scheduling while atomic` in
  `sun20i_pwm_apply` (kernel 7.1.5, H700); logs were unrecoverable pre-change.
- muOS System Diagnostics collector: `MustardOS/internal` `share/task/System
  Diagnostics.sh`.
- Kernel docs on shutdown-hang capture: `docs.kernel.org/power/shutdown-debugging.html`
  (pstore; noted but rejected for RAM-clear reason).
