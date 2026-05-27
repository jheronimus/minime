# SP — a minimal custom firmware base for Anbernic RG35xxSP

SP is an ultra-lightweight, barebones custom firmware (CFW) foundation for the Anbernic RG35xxSP, built on Alpine Linux. 

Rather than acting as a full-featured end-user OS, SP is engineered to be a pristine starting point. It provides a clean, minimal environment to simplify porting graphical game launchers (such as OnionUI, Allium, MinUI, or NextUI) that expect a stock-like Linux firmware base.

---

## Key Features

* **Mainline Linux Kernel:** Built on a modern mainline kernel with custom hardware patches adapted from [Rocknix](https://github.com/ROCKNIX/distribution), optimized to the core using `tinyconfig`.
* **Robust Partitioning:** Uses a single, read-only **EROFS** root partition for system files to ensure absolute stability and speed, paired with a single **FAT32** partition for ROMs and user data.
* **Instant Wireless Connectivity:** Automatically connects to any Wi-Fi network specified in `.sp/config/wifi` on your SD card using `iwd` (migration to `wpa_supplicant` is planned).
* **Developer-Friendly Access:** Autostarts passwordless BusyBox **Telnet** and **FTP** services, allowing you to easily control the system and upload files remotely over the network.

---

## Purpose & Scope

SP is not designed to be a complete, plug-and-play frontend system on its own. Instead, it is a streamlined developer playground and deployment base. It bypasses the bloat of stock firmwares to let you build, port, and run custom graphical interfaces on the RG35xxSP from a clean slate.
