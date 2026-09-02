---
name: clang
description: Use when writing, modifying, reviewing, or formatting C code for MinUI, including the common runtime, UI applications, platform HAL, and companion daemons.
---

# MinUI C Engineering Skill

Engineering standards, conventions, and validation workflows for developing C code in the MinUI ecosystem.

## Quick start

1. Check existing subsystem APIs in [`workspace/all/common/api.h`](file:///home/agent/projects/minime/packages/ui/minui/workspace/all/common/api.h) and utilities in [`workspace/all/common/utils.h`](file:///home/agent/projects/minime/packages/ui/minui/workspace/all/common/utils.h) before writing new functions.
2. Structure new types using the `TypeName` / `TypeName_new` / `TypeName_free(TypeName* self)` OOP pattern.
3. Write C code with hard tabs (`\t`, tab width 4), attached braces, and left-aligned pointers (`Type* var`).
4. Keep comments single-line (`//`), informal, and sectioned with `///////////////////////////////`.
5. Keep function cyclomatic complexity low (target CCN <= 10); decompose complex logic into focused helper functions.
6. Format code in-place using `./scripts/check-minui.sh -i`.
7. Run `just check-minui` or `./scripts/check-minui.sh --complexity` to audit complexity and validate conventions before committing.

## Workflows

### Phase 1: Planning & Subsystem Placement

- Determine where the code belongs based on responsibility:
  - Hardware / OS kernel ioctl interactions -> `workspace/<platform>/platform/platform.c` (implement `PLAT_*` functions).
  - Cross-platform drawing, input, audio, power -> `workspace/all/common/` (extend `GFX_`, `PAD_`, `PWR_`, `SND_`).
  - General string, path, or file parsing -> `workspace/all/common/utils.c`.
  - Application logic & UI flows -> `workspace/all/<app>/` (e.g., `minui.c`, `minarch.c`).
- Consult [`references/ARCHITECTURE.md`](./references/ARCHITECTURE.md) for detailed monorepo layout and build rules.

### Phase 2: Writing & Formatting Code

- Follow the naming rules in [`references/NAMING.md`](./references/NAMING.md):
  - Prefix public APIs with `PLAT_`, `GFX_`, `PAD_`, `PWR_`, `SND_`, `VIB_`, `LID_`, or `LOG_`.
  - Prefix OOP methods with `TypeName_` and take `TypeName* self` as first argument.
  - Name utility functions in `camelCase`.
  - Name constants, macros, and enums in `UPPER_SNAKE_CASE`.
  - Name local variables and fields in `snake_case`.
- Adhere to the code style rules in [`references/STYLE.md`](./references/STYLE.md):
  - Hard tabs for all indentation (never spaces).
  - Attached opening braces on functions and control blocks.
  - Compact single-line `if` statements for early returns and guards.
  - Target CCN <= 10 per function; refactor large event loops and complex switches into tables or helpers.
  - Stack buffers with fixed limits (`char path[MAX_PATH]`) over dynamic allocation.
  - Never write Doxygen docblocks (`/**`, `@param`, `@return`).

### Phase 3: In-Place Formatting

- Automatically format changed C and H files using the canonical `.clang-format`:
  ```sh
  ./scripts/check-minui.sh -i
  ```
- Or format specific files directly:
  ```sh
  mise exec -- clang-format -i path/to/file.c
  ```

### Phase 4: Verification & Gate Validation

- Run the MinUI gate to verify formatting, tab indentation, and complexity audit:
  ```sh
  just check-minui
  ```
- Run a dedicated cyclomatic complexity audit (CCN > 10):
  ```sh
  ./scripts/check-minui.sh --complexity
  ```
- Ensure full repository validation passes:
  ```sh
  just validate-static
  ```
