# ADR 0026: Performance Benchmark Suite

## Status

Accepted

## Context

Optimizing Minime firmware (evaluating memory allocators like `mimalloc` vs musl `mallocng`, tuning kernel governors, scheduler parameters, compiler flags, and filesystem configurations) requires an objective, reproducible, on-device performance measurement suite. Ad-hoc testing or manual timing is imprecise, prone to thermal throttling variances, and lacks a unified comparison metric.

## Decision

Implement a self-contained, firmware- and UI-agnostic C99 benchmarking tool (`/usr/bin/benchmark`) in `src/benchmark/` with host automation via `just benchmark`:

1. **Modular Architecture & Zero Runtime Dependencies**:
   - Written in C99 with POSIX high-resolution timers (`clock_gettime(CLOCK_MONOTONIC)`).
   - Zero external runtime dependencies; builds identically for Alpine (`musl`) and Buildroot (`glibc`).
   - Supports standalone micro-benchmarks, subprocess orchestration for RetroArch / MinUI, and automated output generation.

2. **Comprehensive Workload Matrix**:
   - **Memory & Allocator**: Multi-threaded `malloc`/`free` throughput, small-object churn (64 B to 4 KB), large-block latency, cross-thread freeing, and heap lock contention.
   - **Emulator Cores**: Headless unthrottled RetroArch / libretro benchmark runs (`pcsx_rearmed`, `mgba`, `picodrive`) measuring average FPS and execution duration.
   - **Launcher Operations**: MinUI startup duration, game list scrolling/rendering, and `minarch` core handover latency.
   - **System & Compute**: Integer math, SIMD NEON vector compute, memory bandwidth (`memcpy`/`memset`), and filesystem I/O.

3. **Composite Scoring System ("Minime Index")**:
   - Computes a single "higher is better" index score using a SPEC/Geekbench-style weighted geometric mean of normalized sub-scores against a 1000-point reference baseline:
     - **Emulation**: 40% weight
     - **Memory & Allocator**: 25% weight
     - **Launcher UI**: 20% weight
     - **System & I/O**: 15% weight

4. **CLI Interface & Comparison Mode**:
   - Flags: `--all`, `--category <cat>`, `--quick`, `--json`, `--markdown`, `--save <file.json>`, `--compare <baseline.json>`.
   - Comparison mode loads a saved baseline JSON and outputs delta percentages (+X.X%) and overall index speedup.

5. **Dual-Distro Packaging**:
   - Alpine: `minime/targets/alpine/aports/benchmark/APKBUILD`.
   - Buildroot: `minime/targets/buildroot/external/package/benchmark/`.
   - Host Justfile recipe: `just benchmark [ip]`.

## Consequences

- Direct, empirical verification of allocator switches (e.g. `mimalloc` preloading), kernel parameter tuning, and compiler optimizations.
- Single unified index score enables rapid regression detection in CI and on physical devices.
- Uniform metrics across both Alpine and Buildroot targets.
