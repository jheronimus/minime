# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — glossary of domain terms and invariants.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. Currently: `docs/adr/minime_monorepo_decisions.md`.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/model-domain` skill creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context layout:

```
/
├── CONTEXT.md
├── docs/adr/
│   └── minime_monorepo_decisions.md
├── buildroot/
├── alpine/
└── drivers/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, note it for `/model-domain`.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts the monorepo decisions ADR — worth reopening because…_
