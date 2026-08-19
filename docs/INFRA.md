# Infrastructure & CI/CD (`docs/INFRA.md`)

This document summarizes the Minime GitHub Actions CI/CD workflows, build orchestration, and local quality gates.

## 1. Workflows (`.github/workflows/`)

| Workflow | Trigger | Responsibility | Key Output |
|---|---|---|---|
| [`build.yml`](../.github/workflows/build.yml) | Push to `main`, `workflow_dispatch` | Builds bootloader, cores, UI, OS components, and final image (`.img.zst` / `.tar.zst`). | Uploads to `testing` release |
| [`nightly.yml`](../.github/workflows/nightly.yml) | Cron (`0 4 * * *`) | 15-target matrix regression rebuild across all valid libc/SoC/UI pairs. | Rebuilds all targets |
| [`build-bootloader.yml`](../.github/workflows/build-bootloader.yml) | Called by `build.yml` | Builds & caches U-Boot binaries for all boards (`packages/bootloader/`). | `bootloader-out` |
| [`containers.yml`](../.github/workflows/containers.yml) | Push on container defs | Builds and pushes `minime-musl` and `minime-glibc` builder images to GHCR. | GHCR containers |
| [`sync-kernel.yml`](../.github/workflows/sync-kernel.yml) | Cron (`0 0 * * *`) | Syncs kernel version pins across Alpine and Buildroot configurations. | Commit to `main` |
| [`update-submodules.yml`](../.github/workflows/update-submodules.yml) | Cron (`0 2 * * *`), dispatch | Updates `packages/ui/{allium,minui,muos/frontend}` submodules. | Commit to `main` |

## 2. Monorepo Package Builders (`packages/`)

All build steps follow the linear packaging convention:
- **`packages/bootloader/build.sh`**: Compiles U-Boot and ATF for `h700`, `rk3326`, and `rk3566`.
- **`packages/cores/build.sh`**: Compiles all libretro emulator cores from `packages/cores/*/core.ini`.
- **`packages/components/build.sh`**: Builds the core OS userland for Alpine (`musl`) or Buildroot (`glibc`).
- **`packages/ui/build.sh`**: Builds launcher UIs (MinUI, Allium, muOS) and packages release tarballs.
- **`packages/image/build.sh`**: Stages payload, builds OTA `.tar.zst`, creates FAT32 filesystem, and packages `.img.zst`.

## 3. Local Quality Gates & Commands (`Justfile`)

All validation is local-only and enforced via git hooks (`just install-hooks`):

- **`just validate-static`**: Fast static gate (shellcheck, actionlint, openrc, traits, kernel configs, firmware, patches).
- **`just validate`**: Full gate (`validate-static` + Allium Rust format/clippy, MinUI/Yabause clang-format).
- **`just shell <cmd>`**: Runs remote shell commands on device over SSH (or Telnet fallback).
- **`just ota <ui>`**: Triggers on-device OTA update using `/usr/bin/update.sh`.
- **`just screenshot`**: Captures a live raw PNG frame buffer screenshot over the network.

## See Also
- Monorepo structure: [`AGENTS.md`](../AGENTS.md)
- Traits system: [`docs/traits/TRAITS.md`](traits/TRAITS.md)
- Architectural decisions: [`docs/adr/`](adr/)
