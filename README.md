# SP — a minimal custom firmware for Anbernic RG35xxSP

This is a very barebones custom firmware for Anbernic RG35xxSP, based on Alpine Linux:

- it uses mainline kernel with patches imported from Rocknix Linux, built using tinyconfig;
- it creates a single minimal read-only EROFS partition for your root and a single FAT32 partition for everything else;
- it autoconnects to whatever Wi-Fi network you specify in .sp/config/wifi on your SD card using iwd (I'll switch to wpa_supplicant later);
- it autostarts passwordless busybox telnet and ftp that allows you to remotely control it and upload files.

The point of it is to give a starting point for when you want to port graphical launchers like OnionUI/Allium/MinUI/NextUI that expect a stock Linux firmware. It is not meant to become a full-featured custom firmware by itself.
