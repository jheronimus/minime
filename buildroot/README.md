# Minime — a barebones custom firmware for retro handhelds

A lot of custom firmwares not based on EmulationStation are tightly coupled to specific devices or rely on stock firmware for basic tasks like Wi-Fi management and running RetroArch cores. Minime solves this by providing a unified, decoupled foundation, allowing frontend UIs to be packaged independently—much like desktop environments in Linux distributions.

# Features & Goals
-	Fast to build, easy to modify (based on Buildroot), and requires minimal disk space on the build host.
-	Mainline kernel, based on tinyconfig + cascading platform-specific configurations, currently ~10MB uncompressed.
-	Uses a single FAT32 partition readable on any PC with a read-only erofs rootfs, making updates trivial.
-	Provides essential dependencies: wpa_supplicant, alsa, bluez, libmali, alongside a core set of RetroArch cores and standalone emulators.
- Establishes a standard hardware traits contract to be read by UIs (screen, button layout, input map, system paths).

# How to use

-	Pre-configure Wi-Fi: Before the first boot, add your network credentials to .minime/config/wifi.cfg for automatic connection. The device will start with a passwordless Telnet and FTP server enabled.
-	First Boot: The system will automatically expand the partition to fill the entire SD card.

Development is currently focused on a handful of Anbernic devices that I own: Arc D, RG35xxSP, RG351V, RG351MP.
