# Minime (Custom Linux Firmware)

Minime is a lightweight custom Linux firmware for Anbernic handhelds (RK3326, H700, RK3566).

## Goals & Architecture

- **Dual-Distro Co-equality**: Alpine (musl, arm64) for ultra-fast builds, and Buildroot (glibc, amd64 cross) for closed-source compatibility.
- **Strict Separation**: Clean modular decoupling between the OS runtime and UI launchers (MinUI, Allium, muOS).
- **Deterministic Traits**: Hardware capabilities and display parameters are defined per device in a single trait registry ([`docs/traits/TRAITS.md`](docs/traits/TRAITS.md)).

## Monorepo Layout (`packages/`)

- `packages/bootloader/`: U-Boot/ATF builders (`build.sh`) and per-board configs/blobs (`h700/`, `rk3326/`, `rk3566/`).
- `packages/cores/`: Modular emulator core recipes (`packages/cores/*/core.ini`) and central builder (`build.sh`).
- `packages/components/`: OS targets (`alpine/`, `buildroot/`), shared board overlays, sysctl, OpenRC services, and kernel configs (`boards/`).
- `packages/ui/`: UI submodules (`allium`, `minui`, `muos/frontend`) and packaging builder (`build.sh`).
- `packages/image/`: Single linear packager (`build.sh`) and trait generator (`gentraits.sh`).
- `docs/`: Architecture Decision Records ([`docs/adr/`](docs/adr/)), traits spec ([`docs/traits/TRAITS.md`](docs/traits/TRAITS.md)), and task list ([`docs/TODO.md`](docs/TODO.md)).
- `src/`: Shared out-of-tree drivers (`mali-kbase/`, `libmali/`, `drastic/`).
- `roms/` & `bios/`: Preloaded open-source ROMs package; private console BIOS repo gitignored at `bios/`.

## Local Target Builds

```
make -C packages/components/<alpine|buildroot> components BOARD=<board>  →  compilation only
make -C packages/components/<alpine|buildroot> image BOARD=<board>       →  packages/image/build.sh
```

## Agent Directives

- **No Temporary Workarounds**: Fix local/runner states directly. Never add temporary configs or hacks.
- **Single Source of Truth**: Exactly one canonical location per fact. Point to code directly.
- **Doc Size Limit (5 KB)**: No markdown file in this repository may exceed 5 KB (except `docs/TODO.md`).
- **Minimal UI Intrusion**: Confine UI changes strictly to the Minime platform port directory (`workspace/minime/`, `src/platform/minime/`), with an exception for pruning dead code superseded by Minime's port and traits system.
- **Live Verification**: Deploy OTA updates with `just ota <ui>` or `update.sh <ui>`, and inspect logs via `just shell <cmd>`.
- **Quality Gates**: Run `just validate-static` (fast static gate) or `just validate` (full gate). `--no-verify` is strictly prohibited.
