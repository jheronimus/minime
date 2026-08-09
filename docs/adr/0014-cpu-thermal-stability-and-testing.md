# 0014: CPU Thermal Stability Policy and Qualification Procedure

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-09

---

## Context & Problem Statement

Minime's goal is *highest performance while stable*, but the flagship RK3566
target (Anbernic RG ARC-D) intermittently resets during PCSX-ReARMed playback —
the exact performance-mode workload. Debugging this is harder than it looks
because three separate mechanisms overlap, and the team's mental model did not
match reality:

- **The kernel is the sole enforcer.** Thermal throttling is done in-kernel:
  DTS thermal-zone trips + the `step_wise` governor drive cpufreq/devfreq
  cooling devices. The userspace `thermal-watchdog` service enforces *nothing*
  — it only logs.
- **The watchdog's logs hit the framebuffer TTY.** busybox `syslogd` echoes
  messages to the console by default unless restricted; the `logger` service
  passes no `-l` flag, so warning/critical temperature lines flash over the UI.
- **The default max frequency may exceed what stock voltage can sustain.**
  The RK3566 power-profiling gist (aenertia) measured, at stock voltage on
  passive-cooled devices: 1416 MHz ≈ 73°C (stable), 1608 MHz ≈ 84°C
  (throttle-boundary), 1800 MHz ≈ 6 W peak (thermal shutdown / reset). The
  gist's crash taxonomy spans four root causes: thermal shutdown, HWFFC
  collision, zram storm, and USB/PMIC brownout (an instant reset at low
  temperature, immune to thermal fixes).

Prior architecture: `0005` (governor + frequency traits) defines the 4-speed
model; `0012` (traits schema) carries `cpu_thermal_path` and `cpu_clock_*`;
`0010` (logging) established the `logger` service; `rk3566-undervolt.md`
documents the opt-in undervolt DTBOs.

## Decision

### 1. Kernel thermal trips (RK3566, DTS patch)

Patch the RK3566 DTS thermal zones to Rocknix's proven values, raised from
kernel defaults: **CPU 83°C / 88°C passive**, **GPU 80°C / 88°C passive**.
The TSADC hardware shutdown at 95°C is untouched. `step_wise` remains the sole
throttling mechanism — **no userspace frequency capping anywhere**. A second
userspace throttle would fight the kernel's own cooling devices.

### 2. Default performance target (RK3566)

Change `cpu_clock_performance` from `1800000` to `1608000` in the RK3566 traits
(`minime/boards/rk3566/traits/platform.ini`). Rationale: 1608 MHz is the highest
OPP the gist measured as survivable at stock voltage; 1800 MHz remains
available but only *with* undervolt enabled (undervolt is the gate for the top
OPP). The exact default (1608 vs 1416) is confirmed empirically in phase 1 of
the stability test on RG ARC-D, since the gist's numbers are from different
devices (RGB30/RG353P) with different cooling.

### 3. Undervolt stays opt-in (off by default)

No undervolt level is claimed safe for any silicon: below-threshold voltage
causes *data corruption, not just crashes*, and tolerance varies per chip. The
research doc (`rk3566-undervolt.md`) and Rocknix both default to `off`. Enabling
requires no rebuild: the `l1/l2/l3` DTBOs are compiled into the image and staged
at `.minime/overlays/`; `boot.cmd` applies the level selected in
`.minime/config/device.cfg` via `fdt apply` (common/boot.cmd:92-95). Recovery is
editing that file on a PC.

### 4. Thermal telemetry merged into the `logger` service

- Remove the standalone `thermal-watchdog` OpenRC service (init script in
  `boards/rk3566/overlay/`, backing script in `boards/common/scripts/`).
- Fold its polling loop into the `logger` service as a **second background
  worker** (own pidfile). The `logger` init script (already in
  `boards/common/overlay/`) becomes the single owner; this also fixes the
  dual-distro gap where Buildroot's `post-build.sh` never installed the
  backing script (it installs only `device.sh`/`log-boot.sh`/
  `collect-diagnostics.sh`).
- **Thresholds are derived, not duplicated**: read `trip_point_N_temp` /
  `trip_point_N_type` from the zone dir next to `temp`, locating the zone via
  the existing `cpu_thermal_path` trait (zone index differs per SoC: RK3566
  `thermal_zone0`, H700 `thermal_zone2`). WARNING = first `passive` trip
  (fires exactly when `step_wise` engages = "throttle started"); CRITICAL =
  the `critical` trip. If a zone has no `passive` trip (possible on H700),
  log "throttle-detection only" and use only `critical`. This keeps kernel and
  watchdog incapable of disagreeing and adds no new trait keys.
- **Telemetry**: the worker additionally samples `scaling_cur_freq` vs
  `scaling_max_freq` while temperature is elevated and logs throttle events,
  giving the stability test data beyond raw temperature.
- **File-only logging**: busybox `syslogd` does not echo messages to the
  console (no console option in its usage), and its `-l N` filter drops
  below-N priorities *globally* — they never reach the log file either —
  which would silently silence the thermal monitor. So no severity filter is
  applied; the worker logs through the same `logger` path as any other
  daemon. Verified on-device: with `-l 3` no `user.notice` lines reached
  `syslog.log`; without it they do.

### 5. Two-phase stability test

CI cannot exercise thermals or hardware; this is a physical-device procedure,
documented as the reproducibility contract, driven by `just` recipes over
`just remote`.

**Phase 1 — per config (~15-20 min), short changing loads** (governor ×
undervolt × trips). Mirrors the gist's own protocol but as crash-hunting:
idle → CPU sweep (all-core busy-loop) → GPU burn → memory → **combined**
(CPU+mem+GPU) → **transition-storm** (rapid load on/off, frequency scaling
under load). The transition-storm covers the gist's dominant crash class
(HWFFC collisions, zram storms, burst resets) which a steady soak cannot
reproduce. Pass: no reset; throttle demonstrably engages at the passive trip
(`scaling_cur_freq` drops); temperature stabilizes below critical. A reset's
*signature* — instant at low temperature vs climbing-then-reset — classifies
brownout vs thermal, since brownout is the class thermal policy cannot fix.

**Phase 2 — winning config only (1 hr+)**, sustained combined max load +
`memtester`. Catches sustained-equilibrium and latent memory issues that phase 1
cannot. Pass: no reset, no memory errors, temperature < 90°C (headroom under
the 95°C crit).

**Final acceptance**: a PCSX-ReARMed run (the original failing workload) using
BIOS from the repo-local `bios/` directory.

**Tooling**: `stress-ng` + `memtester` behind a build-time opt-in (Alpine
`world-test` fragment; Buildroot external config), so test images are lean.
Telemetry comes from the merged logger worker via `just get-logs`.

### 6. Kernel config additions (shared fragment)

- `CONFIG_ENERGY_MODEL=y` — lets the kernel estimate per-OPP energy cost. Inert
  on RK3566 (SCMI cpufreq, ATF does not implement `est_power_get`), but enables
  the `power_allocator` thermal governor and possible H700 EAS later.
- `CONFIG_COMPACTION=y` — page compaction required for CMA to succeed under
  memory pressure; both targets use CMA for GPU heaps (Panfrost / `mali_kbase`
  `default_cma_region`).
- `CONFIG_SCHED_ENERGY` (EAS) is **not** added: no populated energy model on
  RK3566, so it would be a no-op.

## Consequences

- **Stable by default**: stock-viable max frequency without gambling on
  undervolt across silicon; 1800 MHz requires the opt-in undervolt path.
- **No second source of enforcement**: the kernel remains the sole throttle,
  and its trips are also the watchdog's log thresholds — drift-free by
  construction.
- **One logging owner**: thermal telemetry, syslog, and the kmsg drain share
  the `logger` service; nothing flashes over the UI.
- **Dual-distro parity**: the Buildroot install gap for the worker is closed.
- **Test tools ship only in test builds**; release images stay lean.
- **Brownout resets are acknowledged as out of scope** for thermal policy;
  only undervolt reduces peak power, and it remains opt-in.
- The `logger` service gains a dependency on the thermal sysfs being present
  (`need modules`; zone must exist before the worker starts).

## Reference

- aenertia, *RK3566 Power Profiling: DMC Devfreq, Power Management, and
  Undervolt* gist (`522cd8df6f0b68a0a2f59f73d5fe3af7`) — thermal trips,
  per-OPP power/temperature table, crash taxonomy, TEO/energy-model notes.
- `docs/research/rk3566-undervolt.md` — undervolt levels, voltage table,
  silicon-lottery warning, recovery procedure.
- `docs/adr/0005-cpu-governor-and-frequency-traits.md` — 4-speed model.
- `docs/adr/0010-logging-and-diagnostics.md` — `logger` service design.
- `docs/adr/0012-traits-schema.md` — `cpu_thermal_path`, `cpu_clock_*`.
