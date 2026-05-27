# SP — a minimal custom firmware for Anbernic RG35xxSP

This is a barebones custom firmware base for the Anbernic RG35xxSP, built on Alpine Linux:

- it uses a mainline kernel with hardware patches imported from Rocknix, optimized using `tinyconfig`;
- it configures a single read-only EROFS partition for the root filesystem and a single FAT32 partition for everything else;
- it automatically connects to the Wi-Fi network specified in `.sp/config/wifi` on your SD card using `wpa_supplicant`;
- it launches a passwordless BusyBox Telnet and FTP server on boot, allowing you to remotely control the console and upload files.

The goal is to provide a clean starting point for porting graphical launchers (such as OnionUI, Allium, MinUI, or NextUI) that expect a stock Linux environment. It is not intended to become a full-featured standalone custom firmware.

