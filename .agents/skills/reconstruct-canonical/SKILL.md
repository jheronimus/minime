---
name: reconstruct-canonical
description: Reconstruct and consolidate decompiled C functions into clean canonical modules in src/*.c, fill gaps, rename variables/functions descriptively, evaluate parity gates, and prune solved assembly functions. Use when consolidating functions into a module, finishing a C subsystem, or running /reconstruct-canonical.
---

# Reconstruct Canonical Module

Decompile assembly functions directly into clean, idiomatic C in `src/<module>.c` and remove completed functions from `src/<module>_asm.S`, maintaining 100.000% whole-library bit-exact parity.

## Acceptance Criteria & Parity Gate

- **Parity Invariant**: Whole-library SHA-256 parity (`just check`) must NEVER regress from 100.000% (`3b27eee0...`).
- **Bit-Exact C (100.000%)**: Zero instruction diffs against target binary. The C implementation replaces the function in `src/<module>_asm.S`.
- **In-Progress / Deferred Functions**: If a function is under development or deferred, keep the reference assembly in `src/<module>_asm.S` and guard the C version in `src/<module>.c` with `#ifndef MATCHING_PARITY` so `just check` remains 100.000% bit-exact.

## Readability Standards

### C Code Readability
- **Domain Names**: Use authentic names from `ref/dwarf/dwarf.json` (`decl_file`, `decl_line`, `params`, `local_variables`). No `func_*`, `DAT_*`, `uVar*`.
- **Typed Structs**: Zero raw pointer math (`*(u32 *)((char *)p + 0x10)` -> `input->current_keys`).
- **Enums & Bitmasks**: Replace magic numbers with named enums/macros (e.g. `INPUT_MODE_REPLAY = 2`).
- **Natural Control Flow**: Replace Ghidra `goto` artifacts with idiomatic `if/else`, `switch`, and guard clauses.
- **Automated Gate**: Verify with `python3 tools/check_readable.py`.

## Workflows

### 1. Triage Next Function
```bash
just next
just bundle <unit>
```

### 2. Decompile & Reconstruct
1. Open `src/<module>.c` and add the clean C implementation.
2. Open `src/<module>_asm.S` and remove the corresponding assembly block for the unit once it matches 100% bit-for-bit.
3. If all functions in a module are reconstructed in C with 100% parity, delete `src/<module>_asm.S`.

### 3. Verify Parity
```bash
just diff <unit>   # Fast feedback on instruction parity
just check         # Authoritative whole-library bit-exact parity
just report        # Update STATUS.md and KPI metrics
```
