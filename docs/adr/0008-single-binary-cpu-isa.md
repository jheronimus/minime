# 0008: Single Shared Binaries Omit RK3566 CPU Optimizations

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-05

---

## Context & Problem Statement

Minime ships **one set of UI and emulator-core binaries per libc** (musl for Alpine, glibc for Buildroot), shared across all three supported SoCs:

| Board | SoC | Cores |
|-------|-----|-------|
| RG35XX SP / RG35XX Plus | Allwinner H700 | 4× Cortex-A53 (ARMv8.0) |
| RG351P/M/V/MP | Rockchip RK3326 | 4× Cortex-A35 (ARMv8.0) |
| RG353P/V, RG Arc, RG503, etc. | Rockchip RK3566 | 4× Cortex-A55 (ARMv8.2) |

The CI pipeline builds each binary once (`build-ui`), then packages the *same artifact* into images for every board (`build-os`). Compile-time CPU flags are baked into the binary at build time, so a single shared binary can only target the **common ISA denominator** of the three SoCs.

Upstream MinUI ships **per-device binaries**, each tuned for its own SoC. Its per-device core patches (e.g. `rgb30` for RK3566) apply SoC-specific `-march`/`-mtune` flags. Minime deliberately does **not** import those flags, so the shared binary runs correctly on all three boards.

## Decision

Build all shared binaries (UI, cores, libmsettings) for the **ARMv8-A baseline** (`-march=armv8-a`, the toolchain default), which is the common instruction set of Cortex-A53/A35/A55. Do **not** use the RK3566/A55-specific CPU optimizations that upstream's `rgb30` patches apply, because `-march`/`-mtune` are compile-time and would render the shared binary incompatible with H700 and RK3326.

### RK3566 optimizations deliberately omitted

| Optimization | Cores it applies to (upstream rgb30) | Effect |
|--------------|-------------------------------------|--------|
| `-march=armv8.2-a` | fceumm, gambatte, gpsp, picodrive, pokemini, race | Enables ARMv8.2 instruction set (newer NEON/SIMD ops, dot-product, etc.) |
| `-mtune=cortex-a55` | fceumm, gambatte, gpsp, picodrive, pokemini, race | Instruction scheduling tuned for the A55 pipeline |

These come from upstream's `rgb30` (RK3566) core patches. H700 (Cortex-A53) and RK3326 (Cortex-A35) are ARMv8.0 and cannot execute `armv8.2-a` code, and their pipelines differ from A55, so these two flags cannot appear in the shared binary.

### Optimizations that *are* usable in the shared binary

- **`-march=armv8-a+crc`** (`crc` = CRC32 instructions): CRC32 is an *optional* ARMv8.0 extension, but **all three SoCs implement it** — Cortex-A53 and Cortex-A35 report `ID_ISAR5.CRC32 = 0x1`, and A55 does too. So the shared binary can safely use `armv8-a+crc` (upstream rgb30 applies it to mednafen_supafaust and pcsx_rearmed).
- **`+simd`** (NEON/AdvSIMD): for AArch64, NEON is **mandatory in the base ARMv8-A architecture**, so `+simd` is a no-op at `armv8-a` — the compiler already emits NEON code. It is not an omitted optimization.

### Per-board tuning that *is* retained

Runtime, traits-driven performance tuning is unaffected by the single-binary constraint and remains in place (see ADR 0014):
- Per-board CPU **governor** (`schedutil` / `performance`) and **max clock** (`cpu_clock_menu/powersave/normal/performance` traits).
- Per-core **dynarec** configuration that is arch-correct for the shared aarch64 binary (gpsp `arm64`, pcsx_rearmed `ari64`, picodrive `aarch64`).

## Consequences

- **H700 and RK3326**: get exactly the correct ISA (ARMv8.0 baseline). No loss.
- **RK3566**: forgoes the `armv8.2-a` and `cortex-a55` compile-time optimizations. The practical impact is small — emulator hot paths are integer/memory-bound and rarely use ARMv8.2-specific instructions, and the dynarec cores (gpsp, pcsx_rearmed, picodrive) generate the perf-critical code at runtime, where compiler flags barely matter. The `crc` extension is *not* omitted (all three SoCs implement CRC32); the shared build may use `armv8-a+crc`.
- **Simplicity**: one binary per libc keeps the `build-ui` → `build-os` contract, one artifact set, one QA cycle.
- **Future option**: if RK3566 performance ever justifies it, ship per-board binary variants with per-SoC `-march`/`-mtune` — a deliberate break of the single-binary contract, revisited on measured evidence rather than assumed gains.

---

## Reference

- Upstream per-device core patches: `workspace/rgb30/cores/patches/*.patch` (RK3566), `workspace/magicmini/cores/patches/*.patch` (RK3326).
- Toolchain default: `gcc -march=armv8-a` (musl and glibc build containers).
- Single-binary pipeline: `.github/workflows/build-musl.yml` / `build-glibc.yml` (`build-ui` artifact consumed by `build-os` for all boards).
- Runtime governor/clocks: `docs/adr/0014-cpu-performance-and-thermal-policy.md`.
