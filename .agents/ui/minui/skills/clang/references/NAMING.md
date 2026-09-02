# C Naming Conventions

Authoritative identifier naming rules for this C codebase.

## Subsystem API Prefixes

Public APIs and hardware abstractions are organized into distinct subsystems. Every public function in a subsystem must use its corresponding uppercase prefix followed by `camelCase`:

| Prefix | Domain / Responsibility | Canonical Examples |
| :--- | :--- | :--- |
| `PLAT_` | Platform hardware abstraction layer (HAL) | `PLAT_initVideo()`, `PLAT_pollInput()`, `PLAT_setCPUSpeed()` |
| `GFX_` | Graphics, surface management, text, rendering | `GFX_init()`, `GFX_flip()`, `GFX_blitButtonGroup()` |
| `PAD_` | Gamepad button & analog stick tracking | `PAD_poll()`, `PAD_justPressed()`, `PAD_isPressed()` |
| `PWR_` | Power management, battery, sleep, CPU clock | `PWR_init()`, `PWR_update()`, `PWR_isCharging()` |
| `SND_` | Audio playback, frame pacing, sample feeding | `SND_init()`, `SND_batchSamples()`, `SND_quit()` |
| `VIB_` | Vibration / haptic motor control | `VIB_init()`, `VIB_setStrength()`, `VIB_quit()` |
| `LID_` | Clamshell lid switch state detection | `PLAT_initLid()`, `PLAT_lidChanged()` |
| `LOG_` | Logging notes and diagnostic output | `LOG_note()`, `LOG_info()`, `LOG_warn()`, `LOG_error()` |

## Object-Oriented C Structs

When encapsulating state and behavior in pseudo-object structures:

- **Struct Types**: Use `PascalCase`:
```c
typedef struct Array {
	int count;
	int capacity;
	void** items;
} Array;
```
- **Self Pointer**: The first argument of every struct method must be `TypeName* self`.
- **Constructor & Destructor**:
  ```c
  TypeName* TypeName_new(void);
  void TypeName_free(TypeName* self);
  ```
- **Methods**: Format as `TypeName_methodName`:
  ```c
  void Array_push(Array* self, void* item);
  void* Array_pop(Array* self);
  int StringArray_indexOf(Array* self, char* str);
  ```

## Utility Functions

Platform-independent string, file, path, or time helpers belong in `utils.h` / `utils.c` and use un-prefixed `camelCase`:
```c
int prefixMatch(char* pre, char* str);
int suffixMatch(char* suf, char* str);
int exactMatch(char* str1, char* str2);
void getDisplayName(const char* in_name, char* out_name);
void putFile(char* path, char* contents);
char* allocFile(char* path);
uint64_t getMicroseconds(void);
```

## Local Variables & Struct Members

- Use `snake_case` for local variables, function arguments, and struct members:
  ```c
  int show_setting = 0;
  uint32_t frame_start = SDL_GetTicks();
  int is_charging;
  ```
- Use concise idiomatic names where clear: `tmp`, `len`, `buf`, `str`, `screen`, `font`, `quit`, `dirty`.

## Constants, Macros & Enums

- Use `UPPER_SNAKE_CASE` for `#define` macros, paths, color triads, and enum entries:
```c
#define MAX_PATH 512
#define ROMS_PATH SDCARD_PATH "/Roms"
#define TRIAD_WHITE 0xff, 0xff, 0xff

enum {
	BTN_ID_NONE = -1,
	BTN_ID_DPAD_UP,
	BTN_ID_A,
	BTN_ID_COUNT,
};
```

## Global Subsystem Contexts

Singleton state for a subsystem is held in a static file-scoped struct instance named after the subsystem:
```c
static struct GFX_Context {
	SDL_Surface* screen;
	SDL_Surface* assets;
	int mode;
	int vsync;
} gfx;

static struct PWR_Context {
	int initialized;
	int can_sleep;
} pwr = {0};
```
