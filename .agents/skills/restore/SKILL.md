---
name: restore
description: Reconstruct DraStic ARM64 functions in Phase 2 using deterministic context, guarded candidates, exact objdiff parity, explicit promotion, and whole-library checks.
---

# DraStic Phase 2 Restoration

Phase 1 canonical module consolidation is complete. This skill governs Phase 2 module-by-module C reconstruction.

## Rules

- Use oracle-derived names, types, and boundaries; do not invent identities.
- Draft in `scratch/` and keep fallback assembly until promotion.
- Use typed fields, named constants, and idiomatic control flow for new C.
- Naked attributes, inline assembly, `__asm__`, and `.inst` are prohibited; exact parity using them is not reconstruction.
- Treat `just equiv` as supporting differential evidence, not proof.
- Treat `just variant`/`just diff` plus `just check` as the parity gates.
- Never remove assembly, commit, or discard unrelated work automatically.

## Workflow

```sh
just doctor
just next
just bundle <unit>
just equiv <unit> --src scratch/<unit>.c
just variant <unit> scratch/<unit>.c
just promote <unit> --src scratch/<unit>.c --apply
just check
just check-readable
just report
```

`just next` selects the first incomplete module in `tools/phase2_modules.json` and prefers existing guarded candidates. `just promote` removes the matching assembly block only after exact per-function parity and a successful whole-library check. Use `just check-module <module>` before moving on.

## Completion

A function counts as reconstructed only when it has active, unguarded C and no fallback assembly for that unit. A module is complete only when all in-scope units meet that rule, no naked wrappers remain, and the build-parity gate passes. `just check` is a build-parity gate, not a C-coverage metric; `STATUS.md` is generated coverage reporting.
