# C Code Style Reference

Authoritative coding conventions for C code in this repository.

## Formatting & Whitespace

- **Indentation**: Hard tabs (`\t`), tab width 4. Never indent code with spaces.
- **Bracing**: Attach opening brace to the statement or function declaration on the same line:
```c
void GFX_flip(SDL_Surface* screen) {
	// ...
}
```
- **Pointers**: Attach the asterisk to the type (`PointerAlignment: Left`):
  ```c
  char* str;
  SDL_Surface* screen;
  Array* self;
  ```
- **Control Flow**:
  - Single-line `if` statements without braces are encouraged for short checks:
    ```c
    if (i == -1) return NULL;
    if (!exists(path)) return;
    ```
  - Compact expressions: `while (c = chars[i])` or `for (int i = 0; i < count; i++)`.
- **Column Limit**: No arbitrary column wrapping. Let lines flow naturally or break at logical semantic points.

## Includes & Headers

- Never sort includes automatically (`SortIncludes: false`). Include order conveys dependency hierarchy:
  1. Standard C library headers (`<stdio.h>`, `<stdlib.h>`, `<stdint.h>`)
  2. POSIX / Linux system headers (`<unistd.h>`, `<fcntl.h>`, `<sys/ioctl.h>`)
  3. External libraries (`<SDL/SDL.h>`, `<msettings.h>`)
  4. Repository common headers (`"defines.h"`, `"api.h"`, `"utils.h"`)
- Always include `"defines.h"` before `"api.h"` (ensures key definitions and macros are present).
- Guard all headers with standard `#ifndef __HEADER_H__` / `#define __HEADER_H__`.

## Comments & Dividers

- **Section Dividers**: Separate major modules, struct suites, or lifecycle sections with a horizontal slash line:
  ```c
  ///////////////////////////////
  ```
- **Comment Style**: Use single-line `//` comments exclusively.
- **Tone**: Informal, lowercase, direct, and pragmatic.
- **Forbidden**: Do NOT write Doxygen-style docblocks (`/** ... */`, `@param`, `@return`, `@brief`). Keep descriptions inline where non-obvious.

## Memory Management & Safety

- Stack buffers with fixed limits are preferred over dynamic allocations:
  ```c
  char path[MAX_PATH];
  char display_name[256];
  snprintf(path, sizeof(path), "%s/%s", dir, file);
  ```
- Ownership: Caller frees returned dynamically allocated strings/structs (document with `// caller must free`).
- Pragmatic DRY: Reuse existing helpers in `utils.h` (`prefixMatch`, `suffixMatch`, `exactMatch`, `exists`, `putFile`, `allocFile`) rather than reimplementing ad-hoc parsing.

## Cyclomatic Complexity

- Target Cyclomatic Complexity Number: **CCN <= 10** for every function.
- Avoid deeply nested conditionals or bloated monolithic functions:
  - Extract inner branch bodies into focused static helper functions.
  - Convert repetitive `if`/`else if` chains into static lookup tables or arrays.
  - Break down multi-device polling and event-handling loops into single-device handlers.
- Checked during validation via `lizard` (`just check-minui` / `./scripts/check-minui.sh --complexity`).

## Compiler & Language Features

- Compiled with `-std=gnu99 -Ofast`.
- Compound literals: Extensively used for structs and arrays:
  ```c
  &(SDL_Rect){SCALE4(1, 1, 30, 30)}
  (char*[]){ "A", "OKAY", NULL }
  (SDL_Color){TRIAD_WHITE}
  ```
- Weak symbols: Use `FALLBACK_IMPLEMENTATION` (`__attribute__((weak))`) for optional platform HAL hooks.
- GCC nested functions: Allowed in localized scopes when helper logic is tightly coupled to a single function.
