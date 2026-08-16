# ADR 0019: Bootsplash — framebuffer logo across the whole boot

* **Status**: Accepted
* **Deciders**: Minime Core Architecture Team
* **Date**: 2026-08-10

---

## Context & Problem Statement

Boot shows the raw console: fbcon paints kernel and OpenRC text until the UI
starts. There is no branded visual state between power-on and the UI.

The bootsplash must display a lowercase `minimē` wordmark and a looping gradient
bar across all panel aspect ratios; start in early initramfs; survive through
switch_root and OpenRC; hide the TTY by default; and allow the user to reveal
TTY logs on demand or on boot failure.

## Decision

### 1. Framebuffer Renderer

A small C program (`src/bootsplash/`) opens `/dev/fb0` and draws geometric block
primitives (` `, `█`, `▀`, `▄`) directly onto the framebuffer (16bpp RGB565 and
32bpp ARGB8888). Character cells scale to the display resolution and center
on screen. The animated gradient bar renders into a small line scratch buffer in
RAM before copying to `/dev/fb0`, eliminating LCD flicker.

### 2. Artwork

Lowercase **`minimē`** rendered as a 30-column × 4-row block grid with aligned
dots on both `i` glyphs and a macron over the `ē`:
```
       ▀        ▀         ▀▀▀▀
█▀█▀█  █  █▀▀█  █  █▀█▀█  █▀▀█
█ █ █  █  █  █  █  █ █ █  █▄▄█
█ █ █  █  █  █  █  █ █ █  █▄▄▄
```

### 3. Progress Bar

An indeterminate looping bar matching the exact width of the wordmark (`track_w =
30 * cell_w`). A cyan-to-blue gradient beam sweeps continuously from left to
right, wrapping back to the left.

### 4. Dual-Phase Lifecycle

- **Binary**: Built from `src/bootsplash/` as a static binary staged into both
  initramfs and rootfs (`/usr/bin/bootsplash`).
- **Initramfs**: Launched by `initramfs-init.sh` after mounting `/dev` and
  setting backlight to max. Terminated cleanly before `switch_root` so files are
  released while framebuffer pixels and kernel VT graphics mode persist.
- **Rootfs**: OpenRC service `etc/init.d/bootsplash` (`before ui`, `boot`
  runlevel) runs the bootsplash in the background during service startup.

### 5. TTY Mode & Volume Key Toggle

The bootsplash sets **`KDSETMODE KD_GRAPHICS`** on `/dev/tty0`, deferring fbcon
painting. Volume keys toggle the VT mode:
- **Vol Up (`KEY_VOLUMEUP`, trait `key_vol_up`)**: Sets `KDSETMODE KD_TEXT` and
  pauses fb rendering so kernel/OpenRC logs are fully visible.
- **Vol Down (`KEY_VOLUMEDOWN`, trait `key_vol_down`)**: Sets `KDSETMODE
  KD_GRAPHICS`, clears fb, redraws `minimē`, and resumes animation.

The process periodically rescans `/dev/input/` to detect input devices
registered late by kernel drivers.

### 6. Handoff & Failure Contract

- `ui` `start()` returns **non-zero** when no UI binary is found.
- The bootsplash monitors OpenRC status files:
  - `/run/openrc/started/ui` → exits cleanly, leaving `KD_GRAPHICS` for UI.
  - `/run/openrc/failed/ui` → switches to `KD_TEXT` and exits to reveal error.
  - 60 s safety timeout → switches to `KD_TEXT` and exits if UI never starts.

### 7. Single-Owner Boot Brightness

The initramfs sets backlight to max from `/sys/class/backlight/*/max_brightness`.
Redundant `echo 5` writes in `initramfs-init.sh` and `init.d/ui` are removed.

## Consequences

- Seamless boot visual from initramfs to launcher UI.
- TTY log is accessible on demand via Vol Up and restored via Vol Down.
- Framebuffer animation is flicker-free via scratch-line buffering.
- Memory footprint is under 40 KB; exits cleanly when UI launches.

## Reference

- Code: `src/bootsplash/`, `minime/boards/common/overlay/etc/init.d/bootsplash`.
- Scripts: `minime/boards/common/initramfs-init.sh`, `overlay/etc/init.d/ui`.
