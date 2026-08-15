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

2. **Comprehensive Hardware Workload Matrix**:
   - **CPU (20% weight)**: Single-threaded and 4-thread multi-core integer ALU and bit-tree compression throughput (MIPS).
   - **Memory (20% weight)**: Tinymembench-style `memcpy`/`memset` bandwidth (MB/s), dynamic allocation churn (ops/s), and pointer-chasing random access latency (ns).
   - **GPU (20% weight)**: Direct DRM/KMS plane flip frame rate (`/dev/dri/card0`), OpenGL ES shader and texture geometry rasterization (FPS), and Vulkan ICD probe.
   - **Storage (20% weight)**: Direct I/O sequential write/read bandwidth (MB/s) and random 4 KB IOPS latency on target filesystem (`/mnt/sdcard`).
   - **Network (20% weight)**: Full-duplex socket stream throughput and network stack bandwidth (MB/s).

3. **Composite Scoring System ("Minime Index")**:
   - Computes a single "higher is better" index score using a SPEC/Geekbench-style geometric mean of normalized sub-scores against a 1000-point reference baseline (20% per category).

4. **CLI Interface & Comparison Mode**:
   - Flags: `--all`, `--category <cpu|mem|gpu|storage|net>`, `--quick`, `--json`, `--markdown`, `--save <file.json>`, `--compare <baseline.json>`.
   - Comparison mode loads a saved baseline JSON and outputs delta percentages (+X.X%) and overall index speedup.

5. **Dual-Distro Packaging**:
   - Alpine: `minime/targets/alpine/aports/minime-benchmark/APKBUILD` (binary installed to `/usr/bin/benchmark`).
   - Buildroot: `minime/targets/buildroot/external/package/benchmark/` (binary installed to `/usr/bin/benchmark`).
   - Host Justfile recipe: `just benchmark [ip]`.

## Consequences

- Direct, empirical verification of allocator switches (e.g. `mimalloc` preloading), kernel parameter tuning, and compiler optimizations.
- Single unified index score enables rapid regression detection in CI and on physical devices.
- Uniform metrics across both Alpine and Buildroot targets.
