---
name: cleanup
description: Scan the Minime monorepo and its forks for accumulated debt after long multi-agent feature sessions — dead code, duplication, unjustified drift from upstream, leftover debugging code, dirty in-place fixes, broken responsibilities, and bespoke reimplementations of available dependencies. Group findings into topics, render them as a Markdown review report with cleanup potential and risk factor per change, then deliver the selected topics as reviewed-ready PRs (one per repo touched) with analysis, criteria evaluation, and an on-device verification checklist. The agent never commits or merges; it only delivers PRs and issues. Use after heavy parallel feature work, when the codebase feels messy, or when fork-maintenance burden (rebasing MinUI/Allium/yabause/drastic against upstream) has grown.
---

# Cleanup

A lazy-senior-dev pass over the whole monorepo: delete what should not exist, move
what is in the wrong place, and prove that every remaining change is justified. The
agent **never commits to any repo**. Worst case is a rejected PR — that is cheap
and fine. The human (or a local agent with hardware) reviews and live-tests before
merging.

## Process

1. **Scan** every region (Scope below) and collect findings for all categories.
2. **Form topics** — group findings by root cause, with a cross-region impact pass
   per topic.
3. **Render the review report** (below) and present it.
4. **Select** — the human picks which topics to implement (or the headless invoker
   pre-selects).
5. **Deliver** — PRs and issues for the selected topics, per the deliverables
   rules.

## Scope

Full monorepo by default, including all forks. The invoker may scope a run to a
single region; even then, trace cross-region impact (below) and report it — never
fix one region in isolation from its consumers.

Regions and their upstream baselines:

| Region | Port boundary | Upstream baseline |
|---|---|---|
| `minime/` (this repo) | n/a — the project itself | none (firmware owns all hardware support) |
| `packages/ui/minui` | `workspace/minime/`, `workspace/all/` | https://github.com/shauninman/MinUI (`main`) |
| `packages/ui/allium` | `crates/common/src/platform/minime`, `crates/play/src/platform/minime` (feature `minime`) | https://github.com/goweiwen/Allium (`main`) |
| `src/yabause` | `yabause/src/libretro/` (ours), `libchdr/` (vendored) | `upstream` branch of the fork (vanilla tarballs) |
| `src/drastic` | per ADR 0024 | record a vanilla baseline if none exists |

Fetch the upstream baseline at run time (or use the fork's configured upstream
remote, e.g. `upstream-main` in minui). Diff the fork's `main` against it. For
yabause, core files in `yabause/src/` must stay **byte-identical** to the
`upstream` branch except a documented fix set — any drift there is a finding.

## The guardrail

Code that diverges from upstream **outside** the port boundary may exist only if it
is one of:

1. a **genuine bugfix or optimization** of upstream code (must carry evidence: an
   ADR, a commit message, or a measured on-device result — not a bare claim);
2. **impossible to make work with Minime's architecture** otherwise — **and** it is
   not a workaround for something broken *in Minime*. If it papers over a Minime
   bug, the fix belongs in Minime, not in the consumer (that is a broken
   responsibility);
3. a **new feature**.

Any divergence that is none of these is **slop**: either remove it, move it into the
port boundary, or (when it is justified but undocumented) add the missing
documentation. When in doubt, prefer deletion.

## Finding categories

1. **No-op / dead code** — functions, variables, files, configs declared but never
   used. Includes dead build targets, unused patches, and `#if 0`/commented blocks.
2. **Duplicated code** — a new function re-implementing an existing one, repeated
   logic shapes (esp. quirk-handling) across files, copy-pasted constants.
3. **Stray from upstream** — shared-code changes that fail the guardrail above.
4. **Debugging code** — logs, dumps, sleeps, env-gated checks, temporary assertions
   added for a debug session and not needed in normal operation.
5. **Dirty in-place fixes** — symptom patches that should be root-cause fixes,
   fragile and undocumented, landing in the wrong layer; repeated per-consumer
   hacks for one underlying issue (e.g. each UI/emulator/tool applying its own
   screen rotation because the firmware does not own it).
6. **Broken responsibilities** — a component touching things outside its remit, or
   one feature with several competing owners. Firmware owns hardware support;
   UIs/emulators/tools do not implement device quirks.
7. **Bespoke instead of a dependency** — a reimplementation of a stdlib/OS/toolchain
   facility where a lightweight dependency already exists. Check the target's
   package repos (Alpine `aports`, Buildroot) for availability and size before
   proposing; prefer the minimal, already-available thing over adding a new dep.

## Detection guidance

- **Dead code** — compile the region and read warnings (`-Wunused-function`,
  `cargo` dead-code warnings, shellcheck). Grep each candidate identifier across
  the **whole monorepo including the other forks** before calling it dead; respect
  exported symbols (external/link-time callers), macro-generated use, and
  `__attribute__((used))`. "Unused" via one build config may be used in another
  (feature flags, both distros, both UIs).
- **Duplication** — grep for identical error strings, setup/teardown sequences, and
  the same numeric literals/quirks in multiple consumers. If the same quirk appears
  in 2+ consumers, suspect a responsibility problem (category 6), not duplication.
- **Stray** — walk `git diff` of fork `main` vs baseline; classify every hunk with
  the guardrail. Pay attention to **stale workarounds**: upstream may now ship a
  native fix that makes one of our patches obsolete — those become deletions.
- **Debug code** — `printf`/`fprintf`/`eprintln!`/`log` noise, `usleep`/`sleep`
  inserted for timing, dump-to-file blocks, `#ifdef DEBUG`/`--verbose` leftovers.
  Distinguish *diagnostics that ship on purpose* (system logs, `boot.log`) from
  session-only noise.
- **In-place fixes** — comments containing "hack", "workaround", "temporary",
  "TODO(fix)", "due to minime"; fixes placed in the consumer that should be in the
  firmware; `sleep`/polling where an event or service gate exists.
- **Responsibilities** — map each trait/config/service to its owners; flag anything
  with 2+ owners or with ownership in the wrong layer (UI doing hardware work).

## Topic formation

Group findings into **topics** — one coherent problem class per topic. A topic may
span repos. Rules:

- One topic = one root cause. If a scan finds 20 dead functions scattered across
  minarch and the libretro glue, that is one "dead code in minui" topic, not 20.
- Every topic must include a **cross-region impact pass**: enumerate the consumers
  of every file you touch (traits → all UIs; init services → UIs' tools; build
  changes → both Alpine and Buildroot; core changes → all emulator frontends).
  Deliver coordinated fixes as part of the topic, or explicitly prove consumers
  unaffected. Example: changing a wifi init script or iwd config requires checking
  the Allium/MinUI wifi tools that read `config/wifi/enabled` and speak `iwctl`,
  and delivering compatible changes if the fix breaks them.
- Keep topics small enough to review in one sitting. Split anything that mixes an
  architectural move with a mechanical cleanup.

## Review report

Before delivering anything, render the whole review as a **Markdown report** so a
human can read every topic and pick what to implement. Markdown renders natively in
VS Code (and GitHub) with no CDN or network. Write it to the session folder:
`docs/cleanup/<YYYY-MM-DD>/report.md` (create the folder; if the datestamp already
exists, append `-2`, `-3`, …). This is the session's documented record. The agent
writes but never commits — committing the session record is the human's call. State
the absolute path in your reply.

Report structure:

- **Header** — run summary as a Markdown table: regions scanned, topics found,
  totals (estimated SLOC removable, files removable).
- **One section per topic** (`## <n>. <title>`), with the risk badge, category tags,
  and recommendation strength as bolded inline labels, then labelled lines:
  - **Problem** — root cause and evidence.
  - **Solution** — what the PRs will do.
  - **Cleanup potential** — estimated SLOC delta (before/after), files removed,
    dependencies removed.
  - **Files** — which files/regions change.
  - **Risk factor** — badge + one line on what drives it (surface: repos, files,
    behavior change, contract surface). Risk is *information for the reviewer*,
    not a self-imposed gate — the agent may implement any topic the human selects.
  - **Criteria** — quick verdicts on SLOC, complexity, features, reliability.
  - **Cross-region impact** — consumers traced; coordinated changes needed.
  - Separate sections with `---`.
- **Top recommendations** — which topics to do first and why.

Risk factor rubric (scored by the surface of the change):

| Risk | Surface |
|---|---|
| Low | one region, behavior-preserving (deletions/moves), port-boundary or internal-only, no init/service/trait/build touch |
| Medium | one region with a real behavior change, or shared fork code with a guardrail justification, or a public symbol/file removed |
| High | multi-repo, architectural ownership change, touches init services/traits/build, or needs on-device verification before merge |

After presenting the report, ask the human which topics to turn into PRs
("Which of these should I implement?"). Deliver PRs/issues only for the selected
topics. In a headless run with no human to answer, follow the invoker's instruction
(implement all / selected / report-only) and make the report visible wherever the
run is observed — e.g. link it from the coordinating issue or attach it as an
artifact.

## Session record

Every session folder (`docs/cleanup/<datestamp>/`) contains:

- `report.md` — the review report above.
- `session.md` — a short summary: date, invoker, regions scanned, topics found
  (slug + category + risk), which were selected and delivered (linked to the
  PRs/issues), and decisions or deferred items. Keep it under the 5 KB doc limit;
  the detail lives in `report.md`.

Session records are the local **don't re-discover ledger**: before proposing a
topic, grep `docs/cleanup/*/session.md` for prior coverage alongside the GitHub
issue/PR search.

## Deliverables

- **Single-repo topic** → one PR to that fork's `main`, body per the format below.
- **Multi-repo topic** → one coordinating issue in `jheronimus/minime` (public,
  describing root cause, the guardrail analysis, the affected regions) **plus one
  PR per repo touched**, each linking the issue.
- **Finding the agent cannot turn into a confident diff** (unclear root cause,
  needs hardware evidence to decide the direction) → an issue write-up only, so a
  human with hardware can action it.
- Branch names: `cleanup/<topic-slug>` on each repo. Never bump submodule SHAs —
  `update-submodules.yml` handles that after merges.
- Before opening an issue/PR, search open **and** closed issues/PRs across the
  repos **and** the session records in `docs/cleanup/` for prior coverage of the
  topic (keywords). Do not re-propose a rejected topic unless something changed
  (new upstream fix, new evidence).

## PR body format

Every PR body has exactly these sections:

1. **Summary** — one paragraph: what changed.
2. **Why** — the category (1–7), the evidence, and the root cause.
3. **Upstream guardrail** — if touching shared (non-port) fork code: which of the
   three justifications applies, with evidence. If the change is behavior-
   preserving cleanup inside the port boundary, say so.
4. **Criteria** — evaluate all four:
   - SLOC delta (before/after; measure with `git diff --stat`/`cloc`),
   - complexity removed (was a dirty workaround replaced by a native fix?),
   - features preserved (explicit statement + what you verified),
   - reliability (is the replacement cleaner/more robust, not merely shorter?).
5. **Cross-region impact** — consumers traced; coordinated PRs delivered (link
   them) or "verified unaffected" with the reasoning.
6. **Verification** — build-gate evidence (region compiled with the target
   toolchain, region lint, `just validate` for minime) and, if the change is **not**
   behavior-preserving, a **Verify on device** checklist (what to test, where logs
   land, per the live-test procedure). Behavior-preserving PRs state that plainly.
7. **Caveats** — known ceilings, deliberate simplifications, follow-ups.

## Quality bar

- **Build gate always.** Compile every touched region with its toolchain; pass
  region lint; run `just validate` for anything in `minime/`. Evidence goes in the
  PR. Never open a PR that has not compiled.
- **Behavior-preserving by default.** Prefer deletions and moves over behavior
  changes. Any behavior change is called out in the summary and the verify-on-
  device checklist — the reviewer cannot be surprised by it.
- **Deletion over addition; boring over clever.** Shortest correct diff. A change
  that merely reshuffles code without removing complexity or debt is not a finding.
- **No temporary workarounds** — never add a hack, config, or script to paper over
  the scan; fix the actual code.
