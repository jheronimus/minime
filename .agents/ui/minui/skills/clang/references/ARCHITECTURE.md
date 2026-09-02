# Architecture & Build Conventions

System design patterns and build paradigms for C code in this repository.

## Monorepo & Directory Layout

- `workspace/all/common/`: Common runtime library.
  - `defines.h`: Central hardware-agnostic defines, colors, button bitmasks, UI scale macros.
  - `api.h` / `api.c`: High-level subsystem APIs (`GFX_`, `PAD_`, `PWR_`, `SND_`, `VIB_`, `LID_`, `LOG_`).
  - `utils.h` / `utils.c`: Cross-platform utility functions.
  - `scaler.h` / `scaler.c`: Software display scaling routines.
- `workspace/all/<app>/`: Standalone UI applications.
  - `minui/`: The primary menu launcher (`minui.c`).
  - `minarch/`: Lightweight libretro frontend (`minarch.c`).
  - `clock/`: Visual date/time configuration utility (`clock.c`).
  - `say/`: Splash message and confirmation dialog (`say.c`).
  - `syncsettings/`: Boot-time hardware brightness/volume synchronizer (`syncsettings.c`).
- `workspace/<platform>/`: Platform HAL and companion daemons.
  - `platform/platform.h`: Device-level screen resolution, scale, button mapping.
  - `platform/platform.c`: Low-level implementation of `PLAT_*` functions.
  - `keymon/`: Background button daemon (`keymon.c`).
  - `libmsettings/`: Persistent hardware volume/brightness state (`msettings.c`).
  - `show/`: Boot and splash display tool (`show.c`).

## Architectural Paradigm

- **Clean Decoupling**: Application logic in `workspace/all/` never calls device-specific ioctls or accesses kernel nodes directly; it interacts solely with `PLAT_*` HAL or subsystem APIs.
- **Hardware Traits**: The platform HAL dynamically inspects hardware traits at runtime rather than relying on per-device compile-time workspace forks.

## Build System Conventions

- **Monolithic Compilation**: In application makefiles, all necessary source files compile together in a single `gcc` invocation:
  ```makefile
  TARGET = minui
  INCDIR = -I. -I../common/ -I../../$(PLATFORM)/platform/
  SOURCE = $(TARGET).c ../common/scaler.c ../common/utils.c ../common/api.c ../../$(PLATFORM)/platform/platform.c

  $(CC) $(SOURCE) -o $(PRODUCT) $(CFLAGS) $(LDFLAGS)
  ```
- **No Intermediate Objects**: Standalone application makefiles do not emit `.o` object files; compilation happens directly from sources to the target `.elf` or binary.
- **Compiler Flags**: Always specify `-std=gnu99 -Ofast` (or `-Os -flto`).

## Standard UI Event Loop Pattern

Every interactive UI application follows this deterministic loop:

```c
int dirty = 1;
while (!quit) {
	uint32_t frame_start = SDL_GetTicks();

	PAD_poll();
	if (PAD_justPressed(BTN_B)) quit = 1;

	PWR_update(&dirty, &show_setting, NULL, NULL);

	if (dirty) {
		GFX_clear(screen);
		// Draw UI elements...
		GFX_flip(screen);
		dirty = 0;
	} else {
		GFX_sync();
	}
}
```
