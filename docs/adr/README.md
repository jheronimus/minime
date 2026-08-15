# Architecture Decision Records

Each ADR covers exactly one topic; ADRs are grouped into contiguous topic blocks.
When a topic is addressed across several ADRs, they are merged into a single ADR.

1. **Dual OS & OTA design** — `0001` dual-distro architecture, `0002` OTA
   package format, `0003` on-device update tool.
2. **Build: CI, optimizations & flags** — `0004` build-flow convention,
   `0005` single-binary CPU ISA, `0006` core build optimization flags.
3. **Logger & remote diagnostics tools** — `0007` logging & diagnostics,
   `0008` remote diagnostics tool.
4. **Shared configs & scripts (kernel config, init scripts)** — `0009` OpenRC
   init parity.
5. **Traits system** — `0010` UI contract & traits, `0011` traits schema,
   `0012` H700 device detection.
6. **Storage system** — `0013` FAT32 cluster sizing & image floor.
7. **GPU stack (panfrost vs libmali)** — `0014`.
8. **Networking (self announcement, iwd, ftp, telnet, dropbear)** — `0015`
   iwd, `0016` passwordless services, `0017` mDNS.
9. **CPU performance & thermals** — `0018`.
10. **Boot (optimizations, bootsplash, charger behavior)** — `0019`
    bootsplash, `0020` charger-triggered boot, `0021` H700 PMIC panic.
11. **Libretro cores: shared builder & naming** — `0022`.
12. **YabaSanshiro libretro port** — `0023`.
13. **DraStic libretro port** — `0024`.
14. **UI ports** — `0025` MinUI feature port.
