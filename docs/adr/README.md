# Architecture Decision Records (ADRs)

This directory documents the architectural decisions for the Minime monorepo. Each ADR addresses exactly one topic in a standardized format (`Problem`, `Solution`, `Examples`, `See also`).

| ADR | Topic | Scope |
|---|---|---|
| [`0001-musl+glibc`](0001-musl+glibc.md) | Dual-Distro Architecture | Alpine + Buildroot co-equality |
| [`0002-build-infra`](0002-build-infra.md) | Build Infrastructure & Pipeline | CI/CD, containers, caching, quality gates |
| [`0003-compile-flags`](0003-compile-flags.md) | Compiler Tuning & CPU ISA | ARM64 baseline ISA, LTO, optimization |
| [`0004-updates`](0004-updates.md) | On-Device OTA Updates | Atomic update payload, `/usr/bin/update.sh` |
| [`0005-retroarch-cores`](0005-retroarch-cores.md) | Shared RetroArch Cores | Modular core builds from `core.ini` |
| [`0006-diagnostics`](0006-diagnostics.md) | Diagnostics & Logging | Boot logging, `collect-diagnostics`, `remote` |
| [`0007-boot`](0007-boot.md) | Boot Chain & OpenRC | U-Boot, initramfs, bootsplash, OpenRC |
| [`0008-ui`](0008-ui.md) | UI Architecture & Launchers | MinUI, Allium, muOS decoupled platform ports |
| [`0009-storage`](0009-storage.md) | Storage & Partitions | Read-only EROFS system + FAT32 userdata |
| [`0010-gpu-drivers`](0010-gpu-drivers.md) | GPU Driver Stack | Mali Bifrost kbase + userspace libmali blobs |
| [`0011-networking`](0011-networking.md) | Networking & Wi-Fi | wpa_supplicant, DHCP, mDNS, Dropbear SSH |
| [`0012-power-and-thermal`](0012-power-and-thermal.md) | Power & Thermal Management | Governors, thermal tripping, charger boot |
| [`0013-input`](0013-input.md) | Input Subsystem & Hotkeys | Evdev mapping, traits, keymon, hotkeys |
| [`0014-bluetooth`](0014-bluetooth.md) | Bluetooth Audio & Persistence | BlueZ, BlueALSA, FAT-compatible state, mid-game switching |
