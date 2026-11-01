# Minime Design Goals & Architecture

Minime is an appliance-like, minimal retro handheld OS and launcher built on Alpine Linux and Go + Ebitengine.

## 1. Minimal Flat Frontend (Go + Ebitengine)
* **Single Curated List**: Flat list of 30–50 games maximum; no console categorization or deep nested directories.
* **Appliance-Grade System Menu**: Integrated UI for Wi-Fi management (`iwd` via D-Bus), Bluetooth pairing/status (`bluez` via D-Bus), audio sink selection, and brightness/volume controls.
* **Display & Audio Output**: Seamless HDMI video out detection and Bluetooth A2DP audio switching (via PipeWire/ALSA).
* **Cross-Platform Simulator**: UI must run natively on macOS for rapid development and testing (windowed mode with keyboard and gamepad emulation), matching Allium's simulator concept.
* **DRM/KMS on Device**: Runs directly on Linux DRM/KMS via Ebitengine's native GBM backend without X11 or Wayland compositors.

## 2. Minimal Emulation Runner
* **Minarch-Style Core Launcher**: Minimal runner for libretro cores without exposing raw emulator internals.
* **Opinionated Defaults (Batocera-Style)**: Abstract away complex core options; expose only essential, high-impact user settings (aspect ratio, filters, remapping).
* **Efficient PSX Rewind on Cortex-A53 (H700)**: PSX rewind must run smoothly without stuttering or audio crackle. Achieved via delta compression, dirty page tracking (`userfaultfd`), or spaced keyframe snapshots rather than full frame-by-frame RAM serialization.

## 3. Dynamic OS & Hardware Trait Discovery
* **Zero-Config Porting**: The launcher adapts to hardware traits discovered at runtime from standard Linux subsystems instead of hardcoded board tables:
  * Display: DRM/KMS sysfs (`/sys/class/drm/card0-*`) for resolution, rotation, and connector status.
  * Input: Linux `evdev` (`/dev/input/event*`) combined with standard SDL `gamecontrollerdb` mappings.
  * Power: `/sys/class/power_supply/*` for battery status and charging states.
  * Connectivity: D-Bus interfaces for network and Bluetooth.
* **Porting Boundary**: Adding a new handheld device should require only a kernel/U-Boot build and appropriate device tree (`.dts`), requiring zero changes to the launcher codebase.

## 4. Immutable Alpine Foundation
* **OS Base**: Pure Alpine Linux minirootfs with musl libc and Mesa Panfrost GPU acceleration.
* **Storage**: Single FAT32 SD card partition (`.minime/`) with initramfs staging and automatic first-boot partition expansion.
