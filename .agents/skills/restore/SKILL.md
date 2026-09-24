---
name: restore
description: Reconstruct DraStic ARM64 functions in Phase 1 (functional equivalence via Unicorn fuzzing under #ifndef MATCHING_PARITY).
---

# DraStic Phase 1 Code Restoration

Reconstruct assembly functions from `src/*_asm.S` into clean, readable, canonical C in `src/<module>.c` under `#ifndef MATCHING_PARITY` and verify functional equivalence using Unicorn fuzzing (`just equiv`).

## Reconstruction Directives

1. **Clean & Idiomatic C**:
   - Write clean, readable C using types and structs from `src/include/`.
   - Use authentic names from the DWARF oracle / bundle; do not invent identities.
   - Zero raw pointer math; use typed struct pointers and named constants.
   - For vectorized raster/blitter code, use standard `<arm_neon.h>` intrinsics (`vld1q_*`, `vst1q_*`, etc.) directly.
   - Naked functions, inline assembly (`__asm__`), and `.inst` in C bodies are strictly prohibited.

2. **Phase 1 Guarding & Verification**:
   - Always wrap newly authored C implementations under `#ifndef MATCHING_PARITY`.
   - Keep fallback assembly in `src/<module>_asm.S` intact so whole-library parity (`just check`) never breaks.
   - Verify functional correctness using `just equiv <unit>`.
   - Verify pure-C compilation across modules using `just check-c`.

3. **No Phase 2 Token Burn**:
   - Do NOT spend time adjusting compiler flags, register allocations, or instruction orders to match `objdiff`. That belongs to Phase 2 binary polish.

## Workflow

```sh
just doctor                         # Verify toolchain, manifest, and environment
just next --status ASM              # Triage next assembly function needing C
just bundle <unit>                  # Display assembly, DWARF types, and signatures
# Implement clean C in src/<module>.c under #ifndef MATCHING_PARITY
just equiv <unit>                   # Stage 1 gate: Unicorn functional equivalence fuzzing
just check-c                        # Verify all canonical C modules compile cleanly
just check                          # Safety gate: whole-library bit-exact parity preserved
just report                         # Regenerate Phase 1 coverage metrics
```
