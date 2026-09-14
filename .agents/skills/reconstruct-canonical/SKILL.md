---
name: reconstruct-canonical
description: Reconstruct and consolidate decompiled C functions into clean canonical modules in src/*.c, fill gaps, rename variables/functions descriptively, evaluate parity gates (100% or deferred 99% criteria), and prune solved slices. Use when consolidating functions into a module, finishing a C subsystem, or running /reconstruct-canonical.
---

# Reconstruct Canonical Module

Consolidate isolated function slices into clean, idiomatic, canonical C modules in `src/<module>.c`, enforce naming and readability standards, evaluate parity gates, and prune source slices.

## Acceptance Criteria: 100% vs 99% Deferred

Whole-library SHA-256 parity (`just check`) must NEVER regress from 100.000%.
Individual functions within a module must satisfy one of two gates:

1. **Bit-Exact (100.000%)**: Zero instruction diffs in `diff_unit`. Linked directly into parity build.
2. **Deferred Canonical (>= 99.0% / < 5 diffs)**: Promoted to `src/<module>.c` and tracked in `tools/skip_deferred.txt` only when:
   - **Semantic Equivalence (100%)**: All branches, registers, side effects, and calculations are complete.
   - **Diff Family**: Diffs in `diff_unit --diagnose` are strictly commutative swaps (`orr`, `add`) or LLVM `BranchFolding`/`TailMerging` branch shifts. Zero opcode changes, zero unmapped constants.
   - **No Workaround**: Retains reference assembly in `skip_deferred.txt` so `just check` remains 100.000% bit-exact.

## Readability Standards

### C Code Readability
- **Domain Names**: No `func_*`, `DAT_*`, `uVar*`. Use descriptive function and variable names.
- **Typed Structs**: Zero raw pointer math (`*(u32 *)((char *)p + 0x10)` -> `input->current_keys`).
- **Enums & Bitmasks**: Replace magic numbers with named enums/macros (e.g. `INPUT_MODE_REPLAY = 2`).
- **Natural Control Flow**: Replace Ghidra `goto` artifacts with idiomatic `if/else`, `switch`, and guard clauses.
- **Automated Gate**: Must pass `python3 tools/check_readable.py` without warnings.

### ASM Readability (for permanent `skip_asm.txt` units)
- **Standard ARM UAL**: Use symbolic AArch64 mnemonics (`ldr`, `str`, `b.eq`). Never raw `.inst 0x...` opcodes.
- **Symbolic Labels**: Use semantic local labels (`.L_read_loop:`, `.L_exit:`) instead of hardcoded hex offsets (`#0x808fc`).
- **Register Context**: Include register role headers at function entry (`// x0: input, x1: event_type`).

## Quick Start

1. Identify module functions via `tools/manifest.json` and `tools/mine_clusters.py`.
2. Consolidate slice C code and fill remaining gaps in `src/<module>.c` and `src/include/<module>.h`.
3. Apply readability standards; verify with `python3 tools/check_readable.py`.
4. Run `python3 tools/diff_unit.py <unit> --diagnose` for every function in the module.
5. If 100%, prune slice from `src/slices/`. If 99%+ with only layout diffs, record in `tools/skip_deferred.txt`.
6. Verify whole-library SHA-256: `just check`.

## Workflows

### Phase 1: Cluster & Inventory
```bash
python3 tools/mine_clusters.py
grep -i "<module>" tools/manifest.json
```
List which functions are solved in `src/slices/` and which need reconstruction from `ref/asm/text/`.

### Phase 2: Gap Filling & Semantic Decompilation
1. Create or open `src/<module>.c` and header `src/include/<module>.h`.
2. Implement missing functions directly in C using established structs and enums.
3. Compiler: Android NDK r21e Clang 9.0.9 (`-target aarch64-linux-android29 -O3 -funwind-tables -fno-slp-vectorize -fPIC`). Never use GCC or temporary flags.

### Phase 3: Parity Tuning & Compiler Patterns
- **Switch Case Ordering**: Case order in C dictates basic block order and jump-table layout. If a case branches to a shared block, place it after preceding cases to trigger branch sharing.
- **Tail Merging**: Clang merges blocks ending in identical instructions before an exit. Inspect fallthrough vs early `return`.
- **Commutative Operands**: LLVM canonicalizes by complexity (`Instruction > Load > Argument/Register > Constant`). Swapping operand expressions in C can force matching register order.

### Phase 4: Consolidation & Slice Pruning
1. Ensure all functions are defined in `src/<module>.c`.
2. For every 100.000% function: remove `src/slices/func_<addr>.c` (single source of truth in `src/<module>.c`).
3. For any >= 99.0% function with accepted compiler-tail differences: record in `tools/skip_deferred.txt`.
4. Run full validation:
```bash
just check
just validate-static
```
