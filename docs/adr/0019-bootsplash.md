# ADR 0019: Bootsplash — framebuffer logo across the whole boot

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

Boot shows the raw console: fbcon paints kernel/openrc text on `tty1` until
the UI takes the fb, with a text flash even during MinUI→Minarch game
launches. There is no branded moment between power-on and the UI.

The splash must show a `MINIME` ASCII wordmark + a looping gradient bar; work
on every panel (4:3, 3:2, 16:9; landscape/portrait) by centering on the real
framebuffer geometry; start as early as possible — including the initramfs
first-boot phases (probe, partition expansion) that reboot repeatedly; and go
straight from splash to UI, **never showing the TTY** unless asked, but
revealing it on failure so broken boots are diagnosable.

## Decision

### 1. Framebuffer renderer

A small C program opens `/dev/fb0` and draws the art glyph-by-glyph from an
**embedded 8×8 bitmap font** (CP437 shapes). `FBIOGET_VSCREENINFO` gives
geometry + pixel format; the splash computes text columns/rows and centers the
block, so all panels work from one code path. Both 16bpp (RGB565) and 32bpp
(ARGB8888) are handled. The fb is **`mmap`'d directly** — no full-screen
software buffer (a few MB saved; ROCKNIX `rocknix-splash` uses a buffer, which
we avoid). The splash is transient (exits at handoff), so its ~100 KB
static-musl footprint is freed before the UI runs.

### 2. Artwork

Uppercase **`MINIME`** in a banner3 (`#`-block) style, embedded as a string
constant (swappable at build time). Lowercase/macron deferred (figlet macron
placement was fragile).

### 3. Progress bar

An **indeterminate** bar (OpenRC has no progress source): ~half the art
width, centered below it, filling then looping, with a horizontal **color
gradient** (cyan→blue) re-tinted as it animates.

### 4. Both phases — one binary, one init script

- One **static-musl** binary (`src/bootsplash/`, no deps): static is required
  in the initramfs (no libc) and is self-contained, so the same binary runs on
  Buildroot's glibc rootfs — no glibc-static bloat.
- **Initramfs**: launched by `initramfs-init.sh` right after the backlight
  step, before the block-device wait — covering SD enumeration, the DDR3-swap
  path, first-boot probe, and partition expansion. Each `reboot -f` restarts
  it; it dies at `switch_root`.
- **Rootfs**: one OpenRC service `etc/init.d/bootsplash` (`before ui`, boot
  runlevel). No second init script.
- Both targets stage the binary into their rootfs (`/usr/bin/bootsplash`) and
  initramfs (via `system-image.sh`).

### 5. TTY hidden — reveal on demand

The splash sets **`KDSETMODE KD_GRAPHICS`** on `/dev/tty0` as soon as it owns
the fb: fbcon stays deferred, kernel/openrc output is buffered but never
painted. The mode is **kernel VT state**, surviving `switch_root` and the
splash's exit — which also permanently eliminates the MinUI→Minarch flash.
Volume keys toggle it:

- **Vol up** → `KDSETMODE KD_TEXT` — fbcon repaints its scrollback (boot log).
- **Vol down** → `KDSETMODE KD_GRAPHICS` — splash resumes covering.

Input: scan **all** `/dev/input/event*` for `KEY_VOLUMEUP` (115) /
`KEY_VOLUMEDOWN` (114) key-downs (the `key_vol_up`/`key_vol_down` trait
values, 115/114 fallback), ignoring autorepeat — device-agnostic.

### 6. Handoff and failure contract

- `ui` `start()` is made honest: returns **non-zero** when it cannot launch
  the UI (today it returns 0). OpenRC records the outcome natively as
  `/run/openrc/failed/ui` or `/run/openrc/started/ui` — no invented code or
  marker.
- The splash polls those files: **`started/ui` → exit, leaving KD_GRAPHICS**
  (handoff); **`failed/ui` → KD_TEXT and exit** (reveal the error). A hard
  timeout (~60 s) reveals the console if `ui` never resolves.

### 7. Single-owner boot brightness

Brightness is currently written by two places (`initramfs-init.sh` and the
`ui` service, both `echo 5`); the splash would have made a third. Exactly
**one** owner: the initramfs sets it once to **max** from the sysfs
(`/sys/class/backlight/*/max_brightness`), which persists across
`switch_root`. The `ui` service's `echo 5` block is removed (the UI applies
the user's stored brightness after launch). The splash never touches it.

## Consequences

- Branded boot initramfs→UI; TTY never shown by default; the MinUI→Minarch
  flash is eliminated as a side effect.
- Vol keys reveal the boot log on demand; a failed/hung boot reveals the
  console automatically.
- `ui` service honesty (return non-zero on launch failure) is a prerequisite
  and a visible improvement on its own.
- Initramfs grows ~100 KB; no kernel changes (`loglevel=3` + deferred takeover
  already quiet the console).
- Artwork is a build-time constant, so a redesign is a one-line change.

## Reference

- Existing: `minime/boards/common/initramfs-init.sh`, `minime/boards/common/overlay/etc/init.d/ui`.
- New: `src/bootsplash/`, `minime/boards/common/overlay/etc/init.d/bootsplash`.
- Studied: ROCKNIX `rocknix-splash` (16/32-bpp fb handling).
