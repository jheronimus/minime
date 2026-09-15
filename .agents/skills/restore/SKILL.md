---
name: restore
description: Reconstruct and decompile DraStic ARM64 assembly modules into clean, readable, canonical C in src/*.c with clear naming, typed structs, idiomatic control flow, no raw pointer math, no magic numbers, and readable UAL assembly.
---

# DraStic Code Restoration

Decompile assembly functions from `src/*_asm.S` into clean, readable, idiomatic C in `src/<module>.c`, enforce strict readability standards for C and ASM, and maintain 100.000% bit-exact whole-library parity.

## Code Standards

### 1. Clear Naming & Zero Decompiler Artifacts
- **Authentic Symbols**: Use authentic function and variable names from `ref/dwarf/dwarf.json` (`subprograms`, `parameters`, `local_variables`) or the name donor.
- **Zero Obfuscation**: Never leave Ghidra placeholder names (`func_*`, `DAT_*`, `uVar*`, `iVar*`, `param_*`, `lVar*`, `local_*`).
- **Meaningful Variables**: Every local variable and parameter must reflect its domain purpose (e.g., `scanline_idx`, `vram_bank_offset`, `touch_pos_x`, `key_mask`).

### 2. No Raw Pointer Math & Typed Structs
- **Typed Access**: Zero raw byte offset arithmetic (e.g. `*(uint32_t *)((char *)p + 0x18)` -> `engine->control_reg`).
- **Canonical Headers**: Define and calibrate all struct layouts in `src/include/*.h` using DWARF definitions.
- **Strict Typing**: Cast through typed struct pointers, never raw `char *` or `uintptr_t` byte offsets.

### 3. No Magic Numbers
- **Enums & Constants**: Replace hex and integer literals with descriptive named enums or macros (e.g. `REG_DISPCNT`, `VRAM_ENABLE`, `FIFO_EMPTY`, `INPUT_MODE_REPLAY`).
- **Bitfields & Masks**: Use named bitmask constants for bitwise checks and shifts.

### 4. Idiomatic Control Flow
- **No Spaghetti**: Eliminate Ghidra `goto` artifacts, inversions, and unstructured loops.
- **Clean Structure**: Use idiomatic `if / else`, `switch / case`, `for`, `while`, guard clauses, and early returns.

### 5. Readable Assembly (for remaining functions in `src/*_asm.S`)
- **Standard ARM UAL**: Use symbolic AArch64 mnemonics (`ldr`, `str`, `b.eq`, `add`, `csel`), never raw `.inst 0x...` hex opcodes.
- **Symbolic Labels**: Use semantic local labels (`.L_loop:`, `.L_exit:`, `.L_table:`) instead of hardcoded hex offsets (`#0x8280c`).
- **Register Documentation**: Include register role headers at function entry (`// x0: system_state, w1: command, w2: data_len`).

## Acceptance Criteria & Parity Gate

- **Parity Invariant**: Whole-library SHA-256 (`just check`) must NEVER regress from 100.000% (`3b27eee0...`).
- **100% C Replacement**: When a function compiles bit-identically in C, remove its assembly block from `src/<module>_asm.S`.
- **Assembly Elimination**: When all functions in a module are reconstructed in C with 100% parity, delete `src/<module>_asm.S`.
- **In-Progress Guarding**: If authentic C code is being developed but does not yet reach 100% bit match, keep reference assembly in `src/<module>_asm.S` and wrap the C implementation in `#ifndef MATCHING_PARITY`.

## Restoration Workflow

1. **Triage Next Function**:
   ```bash
   just next            # Find next target function / module
   just bundle <unit>   # Print DWARF types, symbols, and reference asm
   ```
2. **Decompile to C**:
   - Implement clean, typed C in `src/<module>.c`.
   - Use structs from `src/include/<module>.h`.
3. **Verify Parity**:
   - Run `just diff <unit>` for fast objdiff verification.
   - Run `just check` for whole-library SHA-256 verification.
4. **Eliminate Assembly**:
   - Remove matching function block from `src/<module>_asm.S`.
   - If module has 0 assembly functions remaining, delete `src/<module>_asm.S`.
   - Run `just report` to update `STATUS.md`.
