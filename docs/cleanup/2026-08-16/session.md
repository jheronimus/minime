# Cleanup session — 2026-08-16

- **Invoker**: manual trial run (validate the cleanup skill)
- **Region**: `minui` (`minime/ui/minui`)
- **Baseline**: `upstream-main` (shauninman/MinUI snapshot); live upstream fetch deferred (no network)
- **Delta**: 97 commits, 1,151 files, +6,646 / −36,937 lines (mostly per-device pruning, ADR 0005/0022/0025)
- **Status**: report delivered, awaiting topic selection

## Topics (13)

| # | Slug | Category | Risk | Recommendation |
|---|---|---|---|---|
| 1 | btn-id-cz-button-label-misalignment | bugfix/slop | Medium | Strong — real shipped bug |
| 2 | minarch-rewind-dead-code | dead-code | Low | Strong |
| 3 | dead-exports-port-common | dead-code | Low | Strong |
| 4 | debug-leftovers | debug-code | Low | Strong |
| 5 | wifi-bt-scan-cycle-duplication | duplication | Low | Worth exploring |
| 6 | brightness-volume-constant-spread | duplication/responsibility | Medium | Strong |
| 7 | power-policy-bypass | responsibility/in-place-fix | Medium | Strong |
| 8 | audio-ownership-alsa-firmware | responsibility | High | Worth exploring (multi-repo) |
| 9 | device-identity-quirks-platform | responsibility | Medium | Worth exploring |
| 10 | platform-teardown-sleep-hacks | in-place-fix | Medium | Worth exploring |
| 11 | gambatte-dmg-grid-tmpfile-ipc | in-place-fix | Medium | Worth exploring |
| 12 | hardcoded-root-workspace-paths | in-place-fix | Low | Strong |
| 13 | document-snd-audio-fix | documentation | Low | Worth exploring |

Estimated total cleanup: ≈ −230 SLOC, 1 file removed (`platform/makefile.copy`).

## Delivered

None yet — awaiting selection (skill requires a human pick before opening PRs/issues).

## Decisions & notes

- ~all divergence is ADR-documented (0025 feature port, 0005 single binary, 0022 cores); only genuine undocumented item is the SND audio fix (topic 13).
- Topic 1 (BTN_ID_C/Z) is the highest-value finding: enum/table misalignment shifts every control binding after B; C/Z un-bindable.
- Topic 8 is the architectural one: ALSA/.asoundrc + H700 DAC quirk should move into Minime firmware init (ADR 0027 principle); needs minime + minui PRs.
- Deferred: stale-workaround re-check vs **live** shauninman/MinUI HEAD (network unavailable) — upstream may have fixed things we still patch.

## Don't re-discover

- Topics 1–13 above; if re-scanned, check this file first.
- Live-upstream comparison (`git fetch` of shauninman/MinUI) still pending — worth a dedicated run.
