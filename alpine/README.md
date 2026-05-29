# Minime — a minimal custom firmware

The goal is to provide a very basic firmware that builds fast and is easy to understand and modify. Minime can be used as base for porting firmware overlays (such as OnionUI, Allium, MinUI, or NextUI) that expect a stock Linux environment. It is not intended to become a full-featured standalone custom firmware.

This is a barebones custom firmware base, built on Buildroot:

- it uses a mainline kernel with hardware patches imported from Rocknix, optimized using `tinyconfig`;
- it configures a single read-only EROFS partition for the root filesystem and a single FAT32 partition for everything else;
- it comes with wpa_supplicant for Wi-Fi, alsa for sound, bluez for Bluetooth, libmali for graphics;
- it launches a passwordless BusyBox Telnet and FTP server on boot, allowing you to remotely control the console and upload files.

The whole system flashes as a single FAT32 partition with a hidden compressed rootfs image.
- modify .system/config/wifi.cfg to provide Wi-Fi name and password
- modify .system/config/device.cfg to specify which DTB file needs to be loaded (currently it boots RG35xxSP v1 by default)
  
On first boot the system will autoexpand to the whole SD card.


