---
name: remote-diagnostics
description: Live on-device screenshot capture, visual inspection, and keypress emulation for Minime firmware, launcher UIs, and emulators.
---

# Remote Diagnostics & Live Visual Inspection

The `remote` tool on Minime targets (`/usr/bin/remote`) allows AI agents and developers to capture live screenshots directly from DRM/KMS hardware planes or the legacy framebuffer without writing to flash storage and simulate keypresses across launchers and emulators.

---

## 1. Fast Command Reference

All commands run from the workspace root against the live test device (IP resolved from `deploy.cfg` or passed explicitly):

```sh
# 1. Capture screenshot to local file (auto-detects DRM with FB fallback)
just screenshot [output.png] [ip]

# 2. Simulate single keypress (default hold: 50ms)
just press <key> [duration_ms] [ip]

# 3. Simulate timed keypress sequence
just key-seq "<sequence>" [ip]

# 4. Direct low-level execution via telnet
just shell "remote screenshot --backend drm --base64"
just shell "remote screenshot --backend fb --base64"
just shell "remote press A --duration 100"
just shell "remote combo MENU,X"
just shell "remote info"
```

---

## 2. Screen Capture & Visual Inspection Workflow

Screenshots are extracted from active DRM/KMS CRTC/planes (`/dev/dri/card0`) or legacy framebuffer (`/dev/fb0`), automatically rotated to match the human player's upright perspective using device traits (`screen_rotation`), encoded to PNG in RAM, and streamed to the host.

### Capture Backends (`--backend <auto|drm|fb>`):
- **`auto` (Default)**: Probes DRM/KMS first to grab hardware-accelerated SDL2/Panfrost/Mesa frames. If no active DRM plane is found, falls back to `/dev/fb0`.
- **`drm`**: Forces capture from `/dev/dri/card0` via DMA-BUF PRIME export. Used for Panfrost, Mali, and KMSDRM launchers.
- **`fb`**: Forces capture from `/dev/fb0`. Used for software-rendered launchers or kernel console inspection.

### Step-by-Step Inspection Procedure:
1. **Capture current screen:**
   ```sh
   just screenshot screenshot.png
   ```
2. **Inspect visually in the environment:**
   Use `view_file` on `screenshot.png` or embed into an artifact markdown report:
   ```markdown
   ![Current Device State](/home/agent/projects/minime/screenshot.png)
   ```
3. **Inspect hardware traits & orientation:**
   ```sh
   just shell "remote info"
   ```

---

## 3. Logical Button Identifiers

The `remote` tool automatically maps logical button names to the device's evdev keycodes using `/mnt/sdcard/.minime/traits`:

| Category | Logical Names | Fallback Linux Keycodes |
| :--- | :--- | :--- |
| **D-Pad** | `UP`, `DOWN`, `LEFT`, `RIGHT` | `KEY_UP` (103), `KEY_DOWN` (108), `KEY_LEFT` (105), `KEY_RIGHT` (106) |
| **Action Buttons** | `A`, `B`, `X`, `Y`, `C`, `Z` | `BTN_EAST` (305), `BTN_SOUTH` (304), `BTN_NORTH` (307), `BTN_WEST` (308) |
| **Shoulder Buttons** | `L1`, `R1`, `L2`, `R2`, `L3`, `R3` | `BTN_TL` (310), `BTN_TR` (311), `BTN_TL2` (312), `BTN_TR2` (313) |
| **System & Media** | `START`, `SELECT`, `MENU`, `POWER` | `BTN_START` (315), `BTN_SELECT` (314), `BTN_MODE` (316), `KEY_POWER` (116) |
| **Volume** | `VOL_UP`, `VOL_DOWN` | `KEY_VOLUMEUP` (115), `KEY_VOLUMEDOWN` (114) |
| **Raw Codes** | Numeric values (e.g. `304`) | Any numeric Linux `KEY_*` code |

---

## 4. Input Emulation Modes

### A. Single Keypress
Simulates button down, sleeps for duration, then button up:
```sh
just press A            # 50ms press
just press START 150    # 150ms press
```

### B. Discrete State (Holds & Releases)
For charging moves, long presses, or holding down buttons:
```sh
just shell "remote down A"
# ... wait or perform other checks ...
just shell "remote up A"
```

### C. Simultaneous Combos
Presses all keys, emits `EV_SYN`, waits duration, and releases in reverse order:
```sh
just shell "remote combo MENU,X"
just shell "remote combo L1,R1,START,SELECT --duration 100"
```

### D. Scripted Sequences
Executes comma-separated timed macros (`KEY:DURATION`, `WAIT:DURATION`, `COMBO:DURATION`):
```sh
# Navigate launcher menu and open first game
just key-seq "DOWN:100,WAIT:200,DOWN:100,WAIT:200,A:100"

# In-game state save and exit
just key-seq "MENU:100,WAIT:300,DOWN:100,WAIT:100,A:50"
```

---

## 5. Automated Verification & Diagnostic Recipes

### Recipe 1: UI Navigation & Layout Validation
Verify launcher rendering, text alignment, and carousel scrolling:
```sh
# 1. Capture initial launcher screen
just screenshot step1_launcher.png

# 2. Scroll through lists
just key-seq "RIGHT:100,WAIT:300,RIGHT:100,WAIT:300,RIGHT:100"
just screenshot step2_carousel.png

# 3. Open settings menu
just press SELECT
just screenshot step3_settings.png
```

### Recipe 2: Emulator Launch & Framebuffer Rendering Test
Verify core initialization and graphical output:
```sh
# 1. Launch selected game
just press A
# 2. Allow core to boot and present initial frames
sleep 3
# 3. Capture running game frame
just screenshot game_frame.png
# 4. Open in-game menu
just press MENU
sleep 1
just screenshot game_menu.png
# 5. Quit back to launcher
just key-seq "DOWN:100,WAIT:100,DOWN:100,WAIT:100,A:100"
```

### Recipe 3: Diagnosing Screen Orientation & Rotation Glitches
If the screen appears upside down or sideways:
1. Compare raw framebuffer vs trait rotation:
   ```sh
   just screenshot rotated_default.png
   just shell "remote screenshot --raw --base64" > raw.b64
   just shell "remote info"
   ```
2. Verify `screen_rotation` in `/mnt/sdcard/.minime/traits`:
   * $0^\circ$: landscape panels (most H700, RK3326 RG351P/M/MP, RG503, RG DS)
   * $90^\circ$: RG Arc-D, RG Arc-S, RG40XX-V, RG351V (verify on-device)
   * $270^\circ$: RG353 family (RG353V/P/M), RG28XX (verify on-device)
   Panel firmware blobs (H700) and the display overlay are described in [ADR 0027](/docs/adr/0027-display-rotation.md).
