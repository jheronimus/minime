# Minime (Custom Linux Firmware)

Minime is a lightweight custom Linux firmware for Anbernic handhelds (RK3326, H700, RK3566).

## Goals & Architecture

- **Dual-Distro Co-equality**: Alpine (musl, arm64) for ultra-fast builds, and Buildroot (glibc, amd64 cross) for closed-source compatibility.
- **Strict Separation**: Clean modular decoupling between the OS runtime and UI launchers (MinUI, Allium, muOS).
- **Deterministic Traits**: Hardware capabilities and display parameters are defined per device in a single trait registry (`docs/traits/TRAITS.md`).

## Monorepo Layout (`packages/`)

- `packages/bootloader/`: U-Boot/ATF builders (`build.sh`) and per-board configs/blobs (`h700/`, `rk3326/`, `rk3566/`).
- `packages/cores/`: Modular emulator core recipes (`packages/cores/*/core.ini`) and central builder (`build.sh`).
- `packages/components/`: OS targets (`alpine/`, `buildroot/`), shared board overlays, sysctl, OpenRC services, and kernel configs (`boards/`).
- `packages/ui/`: UI submodules (`allium`, `minui`, `muos/frontend`) and packaging builder (`build.sh`).
- `packages/image/`: Single linear packager (`build.sh`) and trait generator (`gentraits.sh`).
- `docs/`: Architecture Decision Records (`docs/adr/`), traits spec (`docs/traits/TRAITS.md`), and living task list (`docs/TODO.md`).
- `src/`: Shared out-of-tree drivers (`mali-kbase/`, `libmali/`, `drastic/`).
- `roms/`: Preloaded ROMs package.

## Local Target Builds

- **Alpine**: `make -C packages/components/alpine components BOARD=<board>` then `make -C packages/components/alpine image BOARD=<board>`
- **Buildroot**: `make -C packages/components/buildroot components BOARD=<board>` then `make -C packages/components/buildroot image BOARD=<board>`

### Build Convention
```
make components  →  build.sh (compilation only, no packaging)
make image       →  packages/image/build.sh (packaging only, no compilation)
```

## Agent Directives

- **CI Trigger Model**: Parameter-driven via `build.yml` (`testing` release on `main`) and nightly matrix (`nightly.yml`).
- **No Temporary Workarounds**: Fix local/runner states directly. Never add temporary configs or hacks.
- **Single Source of Truth**: Exactly one canonical location per fact. Point to code directly.
- **Doc Size Limit (5 KB)**: No markdown file in this repository may exceed 5 KB (except `docs/TODO.md`).
- **Minimal UI Codebase Intrusion**: Confine UI changes strictly to the Minime platform port directory (`workspace/minime/`, `src/platform/minime/`).
- **On-Device Live Verification**: Deploy OTA updates with `just ota <ui>` or `update.sh <ui>`, and inspect logs via `just shell <cmd>`.

## Quality Gates & Validation

Run local validation before committing (installed via `just install-hooks`):
- `just validate-static`: Fast static gate (shellcheck, actionlint, openrc, traits, kernel configs, firmware, patches).
- `just validate`: Full gate (`validate-static` + Rust/C formatters).
- **`--no-verify` is strictly prohibited.**

## BIOS ROMs
Console BIOS ROMs live in the private repository `jheronimus/console-bios` (gitignored locally at `bios/`).
