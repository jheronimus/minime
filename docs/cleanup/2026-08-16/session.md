# Cleanup session — 2026-08-16

- **Invoker**: manual trial run (validate the cleanup skill)
- **Region**: `minui` (`minime/ui/minui`)
- **Baseline**: `upstream-main` (shauninman/MinUI snapshot); live upstream fetch deferred (no network)
- **Delta**: 97 commits, 1,151 files, +6,646 / −36,937 lines (mostly per-device pruning, ADR 0005/0022/0025)
- **Status**: topics 1–9 + 11–13 implemented (topic 10 evaluated → no change); commits prepared for `jheronimus/MinUI` `main`; container build + on-device verify pending

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

## Delivered (direct to `jheronimus/MinUI` main, trial-run exception)

- **T1**: C/Z button labels + mappings in `minarch.c` (BTN_ID order fixed).
- **T2**: rewind dead code removed (serialization_quirks, last_rewind_pressed, tautology).
- **T3**: dead exports removed across api/platform/traits/wireless; `BT_quit` kept (bt.c:233 calls it); empty `early:` target dropped (and `make early` from workspace/makefile).
- **T4**: joke log, stray fflush, commented debug, stale comments removed.
- **T5**: `trimWhitespace` + `cmdOutput` in utils; `SCAN_cycle` in api; wifi/bt/power/traits/generic_* use them.
- **T6**: `all/common/settings.h` constants; defines.h/keymon.c/msettings.c consolidated.
- **T7**: sleep poweroff from `power.conf` `auto_shutdown_timeout_ms` (default 15 min, 0 = never).
- **T8**: audio ownership → firmware. New `boards/common/scripts/audio.sh` (init/bt-off/bt-on), installed by both post-build.sh, called by init.d/ui (`audio.sh init` + boot DAC unmute); generic_bt.c + traits.c delegate; `.asoundrc` no longer UI-written.
- **T9**: `is_cubexx` global removed; overscan = `screen_aspect == 1x1` via cached traits.
- **T10**: evaluated → no code change (all five sub-items are correct patterns); removed 2 stray debug comments.
- **T11**: gambatte DMG grid via env command, patch rewritten.
- **T12**: 7 makefiles use `../../$(PLATFORM)/libmsettings` instead of `/root/workspace`.
- **T13**: SND fix comment cites commit 1b210f59 as deliberate divergence.
- Syntax pass: all changed C files + shell scripts OK. Full container build + on-device verify pending.

## Decisions & notes

- ~all divergence is ADR-documented (0025 feature port, 0005 single binary, 0022 cores); only genuine undocumented item is the SND audio fix (topic 13).
- Topic 1 (BTN_ID_C/Z) is the highest-value finding: enum/table misalignment shifts every control binding after B; C/Z un-bindable.
- Topic 8 is the architectural one: ALSA/.asoundrc + H700 DAC quirk should move into Minime firmware init (ADR 0027 principle); needs minime + minui PRs.
- Deferred: stale-workaround re-check vs **live** shauninman/MinUI HEAD (network unavailable) — upstream may have fixed things we still patch.

## Don't re-discover

- Topics 1–13 above; if re-scanned, check this file first.
- Live-upstream comparison (`git fetch` of shauninman/MinUI) still pending — worth a dedicated run.
