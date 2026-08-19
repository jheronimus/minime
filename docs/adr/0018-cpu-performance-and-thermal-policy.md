# ADR 0018: CPU Performance, Governor, and Thermal Policy

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10
* **Consolidates**: former `0005` (governor + frequency traits) and former `0014` (thermal)

---

## Context & Problem Statement

MinUI and Allium define 4 CPU speed levels (`0` menu, `1` powersave, `2` normal,
`3` performance) that map to target clocks, not governor strings. Naively
mapping `<= 1` to the Linux `powersave` governor hard-locks the CPU at its
lowest OPP — 480 MHz on H700 drops Game Boy emulation to ~45 FPS.

On the flagship RK3566 (RG ARC-D), the top OPP at stock voltage causes
intermittent resets under performance-mode workloads (PCSX-ReARMed). Power
profiling measured: 1416 MHz ≈ 73 °C (stable), 1608 MHz ≈ 84 °C
(throttle-boundary), 1800 MHz ≈ 6 W peak (thermal shutdown/reset). The kernel
(DTS thermal trips + `step_wise` governor) is the **sole** throttle; userspace
must not cap frequencies against it. The crash taxonomy also spans HWFFC
collisions, zram storms, and USB/PMIC brownout — the last is instant, cold, and
immune to thermal policy.

## Decision

### 1. Four-speed model via traits

The speed contract lives in per-board `platform.ini` traits
(`cpu_governor_path`, `cpu_clock_path`, `cpu_clock_{menu,powersave,normal,performance}`;
values in `packages/components/boards/{h700,rk3326,rk3566}/traits/platform.ini`):

- Levels `0-2`: write `schedutil` to `cpu_governor_path`, cap the `cpu_clock_*`
  kHz at `cpu_clock_path`.
- Level `3`: write `performance` (locks max clock, zero ramp latency) plus
  `cpu_clock_performance`.

### 2. Kernel is the sole thermal enforcer (RK3566)

DTS trips patched to Rocknix values: **CPU 83/88 °C, GPU 80/88 °C passive**;
the TSADC hardware shutdown at 95 °C is untouched. `step_wise` remains the only
throttle — no userspace frequency capping anywhere.

### 3. Default performance target

`cpu_clock_performance` on RK3566 is `1608000` (was `1800000`) — the highest
OPP survivable at stock voltage. 1800 MHz remains available **only** with
undervolt enabled.

### 4. Undervolt is opt-in (off by default)

No level is claimed safe (below-threshold voltage corrupts data; tolerance
varies per chip). The `l1/l2/l3` DTBOs are compiled in and applied at boot from
`.minime/config/device.cfg` (`boot.cmd` `fdt apply`); no rebuild to enable.
See `docs/research/rk3566-undervolt.md`.

### 5. Thermal telemetry merged into `logger`

The standalone `thermal-watchdog` service is removed; its loop becomes a second
worker in the shared `logger` service (own pidfile). Thresholds are **derived**,
not duplicated: the zone dir (located via the `cpu_thermal_path` trait; zone
index differs per SoC) is read for `trip_point_*` — WARNING = first `passive`
trip, CRITICAL = `critical` trip (falls back to critical-only if no passive
trip). While hot, the worker samples `scaling_cur_freq` vs `scaling_max_freq`
to log throttle events. No `syslogd -l` severity filter (it drops below-N
priorities globally, which would silence the worker; verified on-device).

### 6. Kernel config (shared fragment)

`CONFIG_ENERGY_MODEL=y` (per-OPP energy cost; inert on RK3566 SCMI cpufreq but
enables the `power_allocator` governor) and `CONFIG_COMPACTION=y` (CMA success
under memory pressure, needed by both GPU heap backends). EAS is deliberately
**not** enabled (no populated energy model on RK3566).

### 7. Two-phase stability test (physical device)

CI cannot exercise thermals; the reproducibility contract is a `just shell`
procedure. **Phase 1** per config (~15-20 min): idle → CPU sweep → GPU burn →
memory → combined → **transition-storm** (rapid load on/off; covers the gist's
dominant crash classes). Pass: no reset, throttle engages at the passive trip,
temperature stabilizes below critical. A reset's *signature* (instant-cold vs
climbing-then-reset) classifies brownout vs thermal. **Phase 2** (winning
config only, 1 hr+): sustained combined load + `memtester`. Final acceptance:
the original PCSX-ReARMed workload. Tooling (`stress-ng`, `memtester`) ships
only in test builds (Alpine `world-test` / Buildroot `test.config`); telemetry
via `just get-logs`.

## Consequences

- Stable at stock voltage by default; 1800 MHz requires the opt-in undervolt path.
- No second enforcement source: the kernel's trips are also the logger's log
  thresholds, drift-free by construction.
- One logging owner (kmsg drain, syslog, thermal telemetry); nothing flashes
  over the UI; the Buildroot missing-worker gap is closed.
- Brownout resets are acknowledged out of scope; only undervolt cuts peak power.

## Reference

- Traits: `packages/components/boards/{h700,rk3326,rk3566}/traits/platform.ini`.
- DTS trips patch: `packages/components/boards/rk3566/patches/linux/`.
- aenertia, *RK3566 Power Profiling* gist (`522cd8df6f0b68a0a2f59f73d5fe3af7`).
- `docs/research/rk3566-undervolt.md`, `docs/adr/0007-logging-and-diagnostics.md`,
  `docs/adr/0011-traits-schema.md`.
