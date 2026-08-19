# Compiler Tuning & Baseline CPU ISA

## Problem
Supporting multiple ARM64 SoC variants (Cortex-A35, Cortex-A53, Cortex-A55) with separate compiler tuning fragments causes code duplication and prevents sharing precompiled emulator core binaries across devices.

## Solution
Adopt a single baseline ISA across all ARM64 builds: `-march=armv8-a+crc+crypto -mtune=cortex-a53`. Standardize aggressive optimization flags (`-O3`, `-flto`, `-fno-plt`, `-fomit-frame-pointer`) across all emulator cores and UI launchers to maximize framerates on low-power silicon.

## Examples
- Standard core compilation flags: `CFLAGS="-O3 -flto -march=armv8-a+crc+crypto -mtune=cortex-a53"`
- Linker flags: `LDFLAGS="-Wl,-O1 -Wl,--as-needed -flto"`

## See Also
- Core builder: [`packages/cores/build.sh`](../../packages/cores/build.sh)
- UI builder: [`packages/ui/build.sh`](../../packages/ui/build.sh)
