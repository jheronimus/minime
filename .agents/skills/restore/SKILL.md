---
name: restore
description: Reconstruct DraStic ARM64 functions in Phase 1 (functional equivalence via Unicorn fuzzing under #ifndef MATCHING_PARITY) and Phase 2 (exact binary parity polish and assembly elimination).
---

# DraStic Code Restoration

Reconstruct DraStic ARM64 functions from fallback assembly (`src/*_asm.S`) into clean, readable, canonical C (`src/*.c`) following the Two-Stage Reconstruction Pipeline.

## Two-Stage Pipeline

1. **Stage 1 (Functional Equivalence / Fuzzy Parity)**:
   - Decompile target assembly into clean, idiomatic C in `src/<module>.c`.
   - Keep the C implementation guarded under `#ifndef MATCHING_PARITY`.
   - Retain fallback assembly in `src/<module>_asm.S` so whole-library bit parity (`just check`) is preserved.
   - Verify functional correctness with `just equiv <unit>` (Unicorn micro-execution fuzzing against original assembly across randomized inputs).

2. **Stage 2 (Binary Parity Polish)**:
   - Tune compiler levers and code structure with `just diff <unit>` or `just variant <unit> <cand>` to reach 100.000% bit-exact objdiff match.
   - Once exact parity is reached, remove `#ifndef MATCHING_PARITY` and delete the corresponding assembly block from `src/<module>_asm.S`.
   - When an entire module reaches 100% C parity, eliminate its `*_asm.S` file.

## Rules

- Use oracle-derived names, types, and boundaries from DWARF / donor; do not invent identities.
- Use typed structs, descriptive enums, and named constants instead of raw byte offsets.
- Naked attributes, inline assembly (`__asm__`), and raw `.inst` hex opcodes in C are prohibited.
- Whole-library bit-exact parity (`just check`) must NEVER regress from 100.000% (`3b27eee0...`).
- Always keep in-progress Stage 1 C guarded under `#ifndef MATCHING_PARITY` until verified for Stage 2 promotion.

## Workflow

```sh
just doctor                         # check toolchain and environment
just next                           # triage next function / module
just bundle <unit>                  # display assembly, types, and dependencies
just equiv <unit> [--src <file>]    # Stage 1: test functional equivalence
just diff <unit>                    # Stage 2: test binary parity match
just promote <unit> --src <file> --apply # promote bit-exact candidate to C
just check                          # verify whole-library bit parity
just report                         # update coverage status
```
