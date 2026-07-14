# RK3566 Kernel Options Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the approved RK3566 kernel option set while retaining `schedutil` as the default CPU frequency governor.

**Architecture:** Keep every requested symbol in the RK3566 board fragment so other boards remain unchanged. Resolve the fragment against Linux 7.0.10 and assert each final Kconfig value.

**Tech Stack:** Linux Kconfig fragments, Buildroot RK3566 board config, GNU Make, LLVM `ld.lld`

---

### Task 1: Enable and verify RK3566 options

**Files:**
- Modify: `minime/external/board/rk3566/tiny-rk3566.config`

- [ ] **Step 1: Add the approved config values**

Add the 19 symbols from `docs/superpowers/specs/2026-06-19-rk3566-kernel-options-design.md` to the RK3566 fragment. Keep `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y` unchanged in the resolved config.

- [ ] **Step 2: Resolve the RK3566 Linux config**

Run the Linux 7.0.10 `merge_config.sh` with `tiny-base.config` followed by `tiny-rk3566.config`, then run:

```bash
PATH="/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH" make O=/private/tmp/minime-rk3566-kconfig ARCH=arm64 LD=ld.lld olddefconfig
```

Expected: `configuration written to .config`.

- [ ] **Step 3: Assert resolved values**

Run one shell assertion that checks all 19 symbols resolve to `y`, `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`, and `CONFIG_ROCKCHIP_ERRATUM_3568002` remains disabled.

Expected: exit status 0 and `RK3566 config assertions passed`.

- [ ] **Step 4: Run repository integrity checks**

```bash
git diff --check
```

Expected: exit status 0 with no output.

- [ ] **Step 5: Report remote validation requirements**

Do not compile firmware locally. Report that the next remote image must verify boot, AMU/BL31 compatibility, RTC, OTP, `/proc/config.gz`, `/dev/watchdog`, and Mali loading.
