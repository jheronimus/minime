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
   - **Diff Family**: Diffs in `diff_unit --diagnose` are strictly commutative swaps (`orr`, `add`), `csel` condition inversions (`hi` vs `lo`), or LLVM `BranchFolding`/`TailMerging` branch shifts. Zero opcode changes, zero unmapped constants.
   - **No Workaround**: Retains reference assembly in `skip_deferred.txt` so `just check` remains 100.000% bit-exact.

## Readability Standards

### C Code Readability
- **Domain Names**: Use authentic names from `ref/dwarf/dwarf.json` (`decl_file`, `decl_line`, `params`, `local_variables`). No `func_*`, `DAT_*`, `uVar*`.
- **Typed Structs**: Zero raw pointer math (`*(u32 *)((char *)p + 0x10)` -> `input->current_keys`).
- **Enums & Bitmasks**: Replace magic numbers with named enums/macros (e.g. `INPUT_MODE_REPLAY = 2`).
- **Natural Control Flow**: Replace Ghidra `goto` artifacts with idiomatic `if/else`, `switch`, and guard clauses.
- **Automated Gate**: Must pass `python3 tools/check_readable.py` without warnings.

### ASM Readability (for permanent `skip_asm.txt` units)
- **Standard ARM UAL**: Use symbolic AArch64 mnemonics (`ldr`, `str`, `b.eq`). Never raw `.inst 0x...` opcodes.
- **Symbolic Labels**: Use semantic local labels (`.L_read_loop:`, `.L_exit:`) instead of hardcoded hex offsets (`#0x808fc`).
- **Register Context**: Include register role headers at function entry (`// x0: input, x1: event_type`).

## Quick Start

1. Identify module functions via `tools/manifest.json`, `ref/dwarf/dwarf.json`, and `tools/mine_clusters.py`.
2. Consolidate slice C code and fill remaining gaps in `src/<module>.c` and `src/include/<module>.h`.
3. Apply readability standards; verify with `python3 tools/check_readable.py`.
4. Run `python3 tools/diff_unit.py <unit> --diagnose` for every function in the module.
5. If 100%, update slice in `src/slices/`. If 99%+ with only layout diffs, record in `tools/skip_deferred.txt`.
6. Verify whole-library SHA-256: `just check`.

## Workflows

### Phase 1: Cluster & Inventory
```bash
python3 tools/mine_clusters.py
grep -i "<module>" tools/manifest.json
python3 -c "import json; d=json.load(open('ref/dwarf/dwarf.json')); [print(v['name'], v.get('decl_line')) for v in d['subprograms'].values() if v.get('decl_file') == '<module>.c']"
```
Extract canonical function and local variable names directly from DWARF before writing code.

### Phase 2: Gap Filling & Semantic Decompilation
1. Create or open `src/<module>.c` and header `src/include/<module>.h`.
2. Implement missing functions directly in C using established structs, DWARF types, and enums.
3. Compiler: Android NDK r21e Clang 9.0.9 (`-target aarch64-linux-android29 -O3 -funwind-tables -fno-slp-vectorize -fPIC -Wall -fstack-protector-strong`).

### Phase 3: Parity Tuning & Compiler Patterns
- **Stack Canaries**: Functions with local buffers or `va_list` require `-fstack-protector-strong` to emit target `tpidr_el0` frames.
- **Hidden Visibility**: When referencing rodata labels in PIC mode, mark externs `__attribute__((visibility("hidden")))` to avoid GOT indirection and emit direct `adrp`/`add`.
- **Condition Inversions**: Min/max ternaries often flip `csel` condition codes (`hi` vs `lo`) and operand order. This is standard LLVM canonicalization (Tier 2).
- **Tail Merging & Switch Ordering**: Case order dictates basic block layout. Sinking identical trailing calls triggers tail-merging.
- **Commutative Operands**: LLVM canonicalizes by complexity (`Instruction > Load > Argument > Constant`).

### Phase 4: Consolidation & Verification
1. Ensure all subsystem functions are consolidated in `src/<module>.c`.
2. Mirror authentic C implementations to `src/slices/func_<addr>.c` for individual unit compilation.
3. Record any >= 99.0% units in `tools/skip_deferred.txt` to guarantee 100.000% target binary match.
4. Run full validation:
```bash
just check
just validate-static
```
