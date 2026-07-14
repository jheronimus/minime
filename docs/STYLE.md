# Style Guide

Style conventions for all code in this project.

---

## C

- `main()` goes first in `main.c`. In all other modules, public functions (matching the header) go first.
- Each module has a single clear responsibility obvious from its name.
- Function naming: `<module>_<action>_<object>` — a function name outside that pattern signals a responsibility leak.
- Each function is prefaced with a comment explaining what it does. Do not duplicate comments in header files.
- No module over 500 LOC. Over 500 is a refactor signal.
- All functions under 20 LOC with at most two levels of nesting.
- No lines longer than 80 characters.
- No magic numbers — use named `const` definitions.
- Handle errors at the top of the function (early return / guard clauses).

---

## Shell (`.sh`, `post-build.sh`, `post-image.sh`, etc.)

- Target `sh`, not `bash` — scripts run in BusyBox `sh` on the target and in the Buildroot build container. Use `#!/bin/sh`.
- Pass `shellcheck --shell=sh --severity=warning` with zero warnings (blocking gate).
- Use `set -e` at the top of every script that runs as a Buildroot hook.
- Quote all variable expansions: `"${VAR}"`.
- No hardcoded paths outside of `board.env` — read env vars instead.
- Source `board.env` at the top of board-specific scripts.

---

## Python (build scripts, utilities)

- Target Python 3. No Python 2 compat shims.
- Pass `flake8` with zero errors (blocking gate — run via `python3 buildroot/buildroot/utils/check-package`).
- Utility scripts in `buildroot/scripts/` that are not Makefile dependencies must be gitignored (`test_otp.py`, `run_telnet.py`, etc.).
- No `print` for structured output — use `sys.stdout.write` or `logging`.
- Keep scripts under 100 LOC; anything larger is likely a Makefile target in disguise.

---

## Makefile

- Use `$(MAKE)` for recursive make calls, never bare `make`.
- Targets that are not filenames must be declared `.PHONY`.
- Board-specific variables are set via `BOARD=<board>` on the command line; never hardcode a board name inside a shared target.
- Document non-obvious targets with a `##` comment on the same line — these feed `make help`.
- Do not add temporary targets or debug targets to the Makefile; use gitignored helper scripts instead.

---

## Kconfig / Defconfig

- Never duplicate an option across multiple board fragments. If a second board needs it, move it to the common fragment first.
  - Kernel options: `buildroot/external/board/common/tiny-base.config`
  - Buildroot options: `buildroot/external/configs/minime_common.config`
- Board-specific options go in `buildroot/external/board/<board>/tiny-<board>.config` or `buildroot/external/configs/minime_<board>.config`.
- After touching any defconfig, validate with `make buildroot-defconfig BOARD=<board>`.
