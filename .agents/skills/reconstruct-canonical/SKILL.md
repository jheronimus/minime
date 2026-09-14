---
name: reconstruct-canonical
description: Reconstruct and consolidate decompiled C functions into clean canonical modules in src/*.c, fill gaps, rename variables/functions descriptively, evaluate parity gates (100% or deferred 99% criteria), and prune solved slices. Use when consolidating functions into a module, finishing a C subsystem, or running /reconstruct-canonical.
---

# Reconstruct Canonical Module

Consolidate isolated function slices into clean, idiomatic, canonical C modules in `src/<module>.c`, enforce naming standards, evaluate parity gates, and prune source slices.

## Acceptance Criteria: 100% vs 99% Deferred

Whole-library SHA-256 parity (`just check`) must NEVER regress from 100.000%.
Individual functions within a module must satisfy one of two gates:

1. **Bit-Exact (100.000%)**: Zero instruction diffs in `diff_unit`. Linked directly into parity build.
2. **Deferred Canonical (>= 99.0% / < 5 diffs)**: Promoted to `src/<module>.c` and added to `tools/skip_deferred.txt` only when all conditions hold:
   - **Semantic Equivalence (100%)**: All branches, registers, side effects, and calculations are complete.
   - **Diff Family**: Diffs in `diff_unit --diagnose` are strictly commutative swaps (`orr`, `add`) or LLVM `BranchFolding`/`TailMerging` branch shifts. Zero opcode changes, zero unmapped constants.
   - **No Workaround**: Retains reference assembly in `skip_deferred.txt` so `just check` remains 100.000% bit-exact.

## Quick Start

1. Identify module functions via `tools/manifest.json` and `tools/mine_clusters.py`.
2. Consolidate slice C code and fill remaining gaps in `src/<module>.c` and `src/include/<module>.h`.
3. Rename all raw identifiers (`func_*`, `DAT_*`, `uVar*`) to descriptive domain names.
4. Run `python3 tools/diff_unit.py <unit> --diagnose` for every function in the module.
5. If 100%, prune slice from `src/slices/`. If 99%+ with only layout diffs, keep in `tools/skip_deferred.txt`.
6. Verify whole-library SHA-256: `just check`.

## Workflows

### Phase 1: Cluster & Inventory

Find all functions belonging to the target module:
```bash
python3 tools/mine_clusters.py
grep -i "<module>" tools/manifest.json
```
List which functions are already solved in `src/slices/` and which need reconstruction from Ghidra/assembly (`ref/asm/text/`).

### Phase 2: Gap Filling & Semantic Decompilation

1. Create or open `src/<module>.c` and corresponding header `src/include/<module>.h`.
2. Extract reference disassembly from `ref/asm/text/func_<addr>.s` and Ghidra output from `scratch/ghidra/`.
3. Implement missing functions directly in C using established structs and enums.
4. Compiler: Android NDK r21e Clang 9.0.9 (`-target aarch64-linux-android29 -O3 -funwind-tables -fno-slp-vectorize -fPIC`). Never use GCC or temporary flags.

### Phase 3: Naming & Readability Gate

Replace reverse-engineering artifacts with domain-accurate names:
- Function names: `func_000777bc` -> `rtc_write`.
- Parameters/locals: `uVar3` -> `pm_flag`, `param_1` -> `rtc`.
- Struct offsets: replace raw pointer arithmetic (`*(u8 *)(rtc + 0x1a)`) with struct fields (`rtc->status1`).
- Enums: replace magic command IDs with descriptive enum values (`RTC_COMMAND_STATUS1`).
- Run readability gate: `python3 tools/check_readable.py`.

### Phase 4: Parity Tuning & Known Compiler Patterns

When tuning a function against target assembly:
- **Switch Case Ordering**: Case order in C dictates basic block memory order and jump-table layout. If a case branches to a shared block (e.g. `b #0x77a70`), move that case after preceding cases so Clang shares the branch rather than duplicating code.
- **Tail Merging**: Clang merges blocks ending in identical instructions before an exit. If the target has inlined stores, inspect block predecessors; avoid common fallthrough if the target used early `return`.
- **Commutative Operands**: LLVM instruction combiner canonicalizes commutative operations by complexity (`Instruction > Load > Argument/Register > Constant`). Swapping operand expressions in C can force matching register order.

### Phase 5: Consolidation & Slice Pruning

Once all functions in the module meet acceptance criteria:
1. Ensure all functions are defined in `src/<module>.c`.
2. For every 100.000% function:
   - Remove `src/slices/func_<addr>.c` (single source of truth in `src/<module>.c`).
   - Ensure it is NOT in `tools/skip_deferred.txt`.
3. For any >= 99.0% function with accepted compiler-tail differences:
   - Add unit id to `tools/skip_deferred.txt` with explanation.
4. Run full validation:
```bash
just check
just validate-static
```
