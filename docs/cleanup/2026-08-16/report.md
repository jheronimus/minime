# Minime Cleanup Review — minui · 2026-08-16

> trial run of the cleanup skill · region: `minui` (`minime/ui/minui`) · baseline: `upstream-main` (snapshot of shauninman/MinUI)

## Summary

| Metric | Value |
|---|---|
| Commits vs upstream | 97 |
| Files in delta | 1,151 |
| Lines | +6,646 / −36,937 (mostly per-device pruning) |
| Topics found | 13 |
| Est. SLOC removable | ≈ −230 |
| Files removable | 1 (`platform/makefile.copy`) |

Most divergence is documented by ADR 0005 / 0022 / 0025 (single shared binary, cores relocation, feature port). The topics below are the undocumented residue. Live-upstream fetch (shauninman/MinUI HEAD) deferred — no network in this run.

**Delivery status (same-day, trial run continuation)** — topics **1–9 and 11–13 implemented**; topic **10 evaluated, no change** (all five sub-items are correct-by-design upstream/MinUI patterns — see §10). Prepared as direct commits for `jheronimus/MinUI` `main` (no PRs, trial-run exception). Container compile + on-device verification pending (no docker/device in this session).

---

## 1. BTN_ID_C/Z button-label misalignment — control bindings broken

- **Category**: bugfix · slop
- **Risk**: **MEDIUM**
- **Recommendation**: **STRONG**

**Problem** — `BTN_ID_C`/`BTN_ID_Z` were inserted mid-enum in `defines.h` (architecture-required), shifting `X..R3` by +2 — but the positional `button_labels[]` table ("must be in BTN_ID_ order") was not updated. Every binding after B maps to the wrong physical button; C/Z are un-bindable. Verified: enum slot 6 = C but `button_labels[7] == "X"`.

**Solution** — insert `"C"` and `"Z"` at the correct indexes so the table matches the enum; check `device_button_names[]` too.

**Cleanup potential** — +3 lines. A real bugfix, not removal.

**Files** — `workspace/all/common/defines.h`, `workspace/all/minarch/minarch.c`

**Risk factor** — behavior change on every device (input configs parse against this table). Needs on-device verification with a shipped pak's `default.cfg`.

**Criteria** — SLOC +3 · complexity fixed · features **restored** (C/Z bindable) · reliability +

**Cross-region impact** — minui only. Affects all devices' shipped `default.cfg` paks — verify a few (GB, MD, PS) after the fix.

---

## 2. Rewind dead code + tautology in minarch.c

- **Category**: dead-code
- **Risk**: **LOW**
- **Recommendation**: **STRONG**

**Problem** — `core.serialization_quirks` is written via `SET_SERIALIZATION_QUIRKS` but never read; `last_rewind_pressed` is write-only; `if (rewinding) { rewinding = 1; Rewind_sync_encode_state(); }` is a tautology (minarch.c:5151).

**Solution** — drop the dead writes; collapse the tautology to `if (rewinding) Rewind_sync_encode_state();`.

**Cleanup potential** — −15 LOC.

**Files** — `workspace/all/minarch/minarch.c`

**Risk factor** — single file, behavior-preserving, port-side feature code.

**Criteria** — SLOC −15 · complexity − · features preserved · reliability =

**Cross-region impact** — none (minui internal).

---

## 3. Dead exports across port + common API

- **Category**: dead-code
- **Risk**: **LOW**
- **Recommendation**: **STRONG**

**Problem** — zero-caller functions/var: `PLAT_getDeviceId()`, `PLAT_hasButtonCZ()`, `MINIME_hasSecondScreen()`, `is_rg34xx`, `GFX_getVsync()`, `PWR_isCharging()`, `PWR_getBattery()`, `BT_hasBluetooth()`, `static int _` (api.c:216); plus `platform/makefile.copy` (5-line unreferenced stub) and the empty `early:` target (minime/makefile:8).

**Solution** — remove each after a whole-tree grep. Keep-or-drop decision on the `wireless.h` public API (`WIFI_connected`/`WIFI_isKnown`/`WIFI_isBusy`/`trim()`): either wire it or delete it — half an API with no caller is the finding.

**Cleanup potential** — −160 LOC estimated. Files removed: `makefile.copy`.

**Files** — `workspace/minime/platform.c/h`, `traits.c/h`, `workspace/all/common/api.c`, `generic_wifi.c`, `generic_bt.c`, `minime/makefile`

**Risk factor** — deletions only; exported symbols checked across all repos. Build gate catches surprises.

**Criteria** — SLOC −160 · complexity − · features preserved · reliability +

**Cross-region impact** — grep whole monorepo (incl. Allium, yabause) before each deletion. `PLAT_hasButtonCZ` stays until topic 1 lands.

---

## 4. Debug leftovers

- **Category**: debug-code
- **Risk**: **LOW**
- **Recommendation**: **STRONG**

**Problem** — `LOG_info("missing assets, you're about to segfault dummy!\n")` (api.c:277); commented-out debug/SDL_GetTicks blocks in api.c/platform.c/clock.c/minput.c; stray `fflush(stdout)` (menu.c:414); stale comments ("based on rgb30 + tg5040 + m17", "lives in minime.c" — no such file).

**Solution** — delete the noise; fix the stale comments. Keep intended diagnostics (boot.log-style logging is fine).

**Cleanup potential** — −25 LOC estimated.

**Files** — `api.c`, `platform.c`, `clock.c`, `minput.c`, `menu.c`, `msettings.c`

**Risk factor** — behavior-preserving deletions in port + new code only.

**Criteria** — SLOC −25 · complexity − · features preserved · reliability +

**Cross-region impact** — none.

---

## 5. wifi.c / bt.c scan-refresh duplication

- **Category**: duplication
- **Risk**: **LOW**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — identical scan/settle/refresh + sorted-rebuild cycles copy-pasted between `settings/wifi.c:95-146` and `settings/bt.c:97-149`. Also three hand-rolled `trim()`s (traits.c, generic_wifi.c, power.c) and pointless `popen` wrappers in generic_*.c.

**Solution** — extract the shared cycle into `common/`; use one trim helper (or `isspace` loop); inline the popen wrappers.

**Cleanup potential** — −20 LOC estimated.

**Files** — `settings/wifi.c`, `settings/bt.c`, `common/generic_wifi.c`, `common/generic_bt.c`, `platform/traits.c`, `settings/power.c`

**Risk factor** — refactor of new feature code; behavior-preserving if extraction is faithful.

**Criteria** — SLOC −20 · complexity − · features preserved · reliability =

**Cross-region impact** — none. Only worth doing if the two tools keep converging (they will).

---

## 6. Brightness/volume constant spread, trait cap ignored

- **Category**: duplication · responsibility
- **Risk**: **MEDIUM**
- **Recommendation**: **STRONG**

**Problem** — `keymon.c:14-17` re-declares `VOLUME_MAX`/`BRIGHTNESS_MAX` from `defines.h` and hardcodes the 0–10/0–20 scale that `msettings.c:86,107` re-clamps; the brightness cap ignores `traits->screen_backlight_max`.

**Solution** — one canonical set of constants in `defines.h`; keymon reads the trait for the brightness cap.

**Cleanup potential** — −5 LOC; mainly a latent-bug fix (devices with `screen_backlight_max < 20` currently get an out-of-range cap).

**Files** — `workspace/minime/keymon/keymon.c`, `libmsettings/msettings.c`, `all/common/defines.h`

**Risk factor** — behavior change for capped devices; verify brightness on one capped device.

**Criteria** — SLOC −5 · complexity − · features preserved · reliability +

**Cross-region impact** — brightness scale is read by `remote`/screenshot tooling? Verify minime tools don't duplicate the scale.

---

## 7. Power policy bypass — api.c hardcode vs power.conf

- **Category**: responsibility · in-place-fix
- **Risk**: **MEDIUM**
- **Recommendation**: **STRONG**

**Problem** — `api.c:1922-1923` hardcodes a 2-minute sleep auto-poweroff (+1 min charging), bypassing the `power.conf` policy the Power tool (`settings/power.c`) writes. Two competing owners of power policy.

**Solution** — api.c reads `power.conf` via the existing `PWR_loadPolicy()` instead of the hardcoded timer.

**Cleanup potential** — ≈0 SLOC; removes the divergent behavior.

**Files** — `workspace/all/common/api.c`

**Risk factor** — behavior change for idle users; verify on-device (sleep/auto-shutdown timings).

**Criteria** — SLOC 0 · complexity − · features preserved · reliability +

**Cross-region impact** — none (minui internal). Verify Power pak writes match what api.c reads.

---

## 8. Audio ownership — ALSA routing + DAC quirk belong in firmware

- **Category**: responsibility
- **Risk**: **HIGH**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — the BT settings PAK writes `/mnt/sdcard/.asoundrc` (bluealsa route + type-hw-card restore) from the UI (`generic_bt.c:39-88`), and `traits.c:348-368` shells to `amixer` hardcoding the H700 "DAC" codec quirk. ALSA routing is hardware support — firmware owns it (ADR 0027 principle; ADR 0014 audio stack).

**Solution** — move .asoundrc generation + codec handling into a minime init service / `bluetooth` service; UI toggles the service gate only. Multi-repo: minui + minime.

**Cleanup potential** — UI −40 / firmware +25 ≈ −15 net.

**Files** — minui: `generic_bt.c`, `traits.c`; minime: new/updated init.d service

**Risk factor** — multi-repo architectural move touching audio on boot; needs on-device verification (BT audio route, game audio after reboot).

**Criteria** — SLOC −15 · complexity − · features preserved · reliability +

**Cross-region impact** — minime `init.d/bluetooth`, `.asoundrc` consumers (ALSA, bluealsa), Allium BT feature reads the same gate. Coordinate with the Allium port if it writes .asoundrc too.

---

## 9. Device-identity quirks in the platform port

- **Category**: responsibility
- **Risk**: **MEDIUM**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — `is_cubexx`/`is_rg34xx` device identity is derived from aspect ratio (`platform.c:124-125`) to drive overscan/scaling in the UI; `screen_aspect` is parsed two ways (file "W:H" vs derived, traits.c:194-210 vs 314-324); wifi/bt status rides the battery thread (`platform.c:957-976`), reading traits directly and bypassing the generic_* backends.

**Solution** — device identity comes from traits (already `screen_aspect`/`screen_rotation` — ADR 0027 direction); one parse path; status reporting through the backends.

**Cleanup potential** — −10 LOC; mostly removing the two-sources-of-truth.

**Files** — `workspace/minime/platform.c`, `traits.c`

**Risk factor** — scaling/overscan behavior for cubexx/rg34xx — on-device verify those two devices.

**Criteria** — SLOC −10 · complexity − · features preserved · reliability +

**Cross-region impact** — traits file is the shared contract (ADR 0010/0011) — Allium reads the same fields. Do not rename trait keys without coordinating.

---

## 10. Platform teardown/sleep hacks

- **Category**: in-place-fix
- **Risk**: **MEDIUM**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — `PLAT_powerOff()` hardcodes `rm -f /tmp/minui_exec; sync; sleep(2)` (platform.c:990-992); UI SIGSTOP/CONTs keymon by name via `killall` (api.c:1896); `on_hdmi = GetHDMI()` per-frame poll (platform.c:817) fights keymon's `watchHDMI` thread; `"wlan0"` fallback when trait absent (generic_wifi.c:36); `CODE_POWER 102` template leftover (platform.h:74).

**Solution** — each is small: proper teardown contract (firmware `device.sh`?), pid-file or socket for keymon control, single HDMI watcher, trait-driven iface, delete template constant.

**Resolved (2026-08-16)** — reviewed each sub-item in code; **no code change**:
- `rm -f /tmp/minui_exec; sync; sleep(2)` in `PLAT_powerOff` is MinUI's loop-break + flush contract (launch.sh:37-51), not a minime hack — kept.
- `killall -STOP/-CONT keymon.elf` — keymon is MinUI's own process (launch.sh:22); the coupled `ignore` skip in keymon.c:83-117 depends on the SIGSTOP signal design — kept.
- `on_hdmi = GetHDMI()` per-frame is the shm producer/consumer (keymon `watchHDMI` writes, UI reads) — the comment "use settings instead of getInt(HDMI_STATE_PATH)" already marks the single source — kept.
- `"wlan0"` fallback in `wifi_interface()` is the sane default when the trait is absent — kept.
- `CODE_POWER 102` is an SDL scancode used for power-wake (api.c:1491); changing it without an on-device scancode capture risks breaking sleep wake — kept, flagged for device verification.
- Removed the two stray debug comments (`// !!!???` platform.c, `// buh` api.c:1886).

**Cleanup potential** — ≈0 SLOC; each is a fragile-pattern removal.

**Files** — `platform.c/h`, `api.c`, `generic_wifi.c`, `keymon.c`

**Risk factor** — sleep/HDMI/poweroff behavior — verify on-device per change.

**Criteria** — SLOC 0 · complexity − · features preserved · reliability +

**Cross-region impact** — `device.sh` (minime overlay) owns shutdown/undervolt — coordinate the poweroff teardown with it.

---

## 11. Gambatte DMG-grid palette via /tmp file IPC

- **Category**: in-place-fix
- **Risk**: **MEDIUM**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — minarch.c:1526 polls `/tmp/dmg_grid_color` written by the gambatte core patch (survived the cores relocation, commit 65d0451c). Cross-process UI↔core communication through a tmp file, run on every color change.

**Solution** — reimplement via the libretro environment/message interface, or an in-process setter — drop the file and the `system()` write.

**Cleanup potential** — ≈0 SLOC; removes a fragile IPC path.

**Files** — `workspace/all/minarch/minarch.c`, gambatte core patch

**Risk factor** — feature behavior on GB DMG games; needs the core rebuilt + on-device verify.

**Criteria** — SLOC 0 · complexity − · features preserved · reliability +

**Cross-region impact** — the gambatte patch is a minui cores patch — coordinate with the shared-cores build (ADR 0022).

---

## 12. Hardcoded /root/workspace build paths

- **Category**: in-place-fix
- **Risk**: **LOW**
- **Recommendation**: **STRONG**

**Problem** — 7 makefiles hardcode `/root/workspace/$(PLATFORM)/libmsettings` (e.g. settings/makefile:40-41) — a machine-specific build root.

**Solution** — reference `libmsettings` via a relative path or a single variable in the workspace makefile.

**Cleanup potential** — ≈0 SLOC; build hygiene (breaks anywhere that isn't `/root/workspace`).

**Files** — `workspace/all/{minarch,minui,minput,settings,clock,say,syncsettings}/makefile`

**Risk factor** — build-only; CI + local build gate.

**Criteria** — SLOC 0 · complexity − · features preserved · reliability +

**Cross-region impact** — minime CI builds the UI in a container at a fixed root — verify the container path matches after the change.

---

## 13. Document the SND audio fix divergence

- **Category**: documentation
- **Risk**: **LOW**
- **Recommendation**: **WORTH EXPLORING**

**Problem** — `api.c:1191-1199,1240-1245` — a genuine bugfix (SND backlog drop + SND_init failure path, commit 1b210f59 restoring an earlier fix) is the only substantive divergence with **no ADR/comment** documenting it. Undocumented = looks like slop to future reviewers.

**Solution** — add a comment (or a one-paragraph ADR entry) citing the commit and the on-device evidence.

**Cleanup potential** — +5 LOC (documentation).

**Files** — `workspace/all/common/api.c`

**Risk factor** — comment-only.

**Criteria** — SLOC +5 · complexity 0 · features preserved · reliability =

**Cross-region impact** — none. Prevents a future cleanup pass from "fixing" the divergence by deleting it.

---

## Top recommendations

1. **#1 BTN_ID misalignment** — a real shipped bug; fix + on-device verify first.
2. **#7 power policy bypass** — removes a divergent behavior with one read of power.conf.
3. **#2 + #3 + #4** — safe deletions, batch into one "minui dead code" pass.
4. **#12 build paths** — zero-risk, unlocks building the UI outside `/root/workspace`.
5. **#8 audio ownership** — the architecturally important one; plan it as its own multi-repo effort (needs firmware change + on-device audio verification).

---

*Generated 2026-08-16 · trial run of the cleanup skill · region: minui · baseline `upstream-main`. Live-upstream fetch deferred (no network); stale-workaround re-checks vs current shauninman/MinUI remain TODO.*
