# Minime (Custom Linux/Buildroot firmware)

Minime is a basic custom firmware for Anbernic handhelds (RK3326/H700/RK3566).

## Goals

- Fast to build and test. Builds completely on Github Actions in under 30 minutes for all images.
- Wide compatibility. Comes in two versions: Alpine (smaller, faster to build), Buildroot (glibc, so compatible with closed source software like libmali, Drastic, Pico-8).
- Automates as much as possible: tests, quality gates, builds, release process.
- Clean modular architecture: strict separation between firmware and UI.
- Implements a trait system: a single text file that describes each device and its specs and is read by the UI. This makes it easies to add Minime support to existing projects (currently Allium and MinUI support Minime).


## What's included

Only the basic components required by launchers: alsa, wpa_supplicant, bluez, telnet, ftp, GPU drivers, etc.

## Monorepo Structure

- `packages/`: Central source of truth for hardware definitions, bootloaders, target software builders, and image packaging.
  - `boards/`: Board definitions, kernel patches, traits, and OpenRC overlays.
    - `common/`: Shared OpenRC services (`overlay/etc/init.d/`), sysctl, wifi config, `device.sh`.
    - `h700/`, `rk3326/`, `rk3566/`: Per-board patches, traits, firmware, `boot.env`, and `genimage.cfg`. Per-device overlay DTS is generated from the traits registry by `packages/image/gentraits.sh` (no `dts/` dirs). The full system design — intent (deterministic traits, no hand authoring, follow mainline not other firmwares), logic, and audit references — is in [`docs/traits-system.md`](docs/traits-system.md); kernel-version evaluation uses the `kernel-review` skill.
  - `uboot/`: U-Boot configs (`config/`), patches (`patches/`), and prebuilt binaries (`out/`).
  - `targets/`: Target software builders.
    - `alpine/`: Core Alpine target build system (`aports/`, `configs/`, `container/`, `Makefile`, `build.sh`).
    - `buildroot/`: Core Buildroot target build system (`external/`, `Makefile`).
  - `build/`: Centralized image assembly (`mkimage.sh`), update package generation (`mkupdate.sh`), and UI assets (`genassets.sh`).
- docs/: Documentation, ADRs (adr/), and specs/research (research/).
- `src/`: Shared source code (libmali GPU userspace, mali-kbase kernel driver).
  - `mali-kbase/`: ARM Mali Bifrost kernel driver source (out-of-tree module).
  - `libmali/`: ARM Mali userspace driver source + proprietary blobs.
- `roms/`: Preloaded ROMs package.

## File Locations & Repository Mapping

Minime supports two build targets: Alpine and Buildroot, housed under `packages/components/`. All shared configuration files, DTS/DTB files, kernel patches, firmware blobs, and hardware traits live in the central `packages/components/boards/` directory. Target build scripts reference or import them directly from there.

For precise paths, consult [docs/MAP.md](docs/MAP.md).

For init scripts, `packages/components/boards/common/overlay/etc/init.d/` is the single source of truth for cross-distro OpenRC services. At build time, target builders copy these init scripts into their rootfs before building `system.erofs`.

## Local Target Builds

Alpine and Buildroot targets are built from their respective directories in `packages/components/` using the two-step build convention:
- **Alpine**: `make -C packages/components/alpine components BOARD=<board>` then `make -C packages/components/alpine image BOARD=<board>`
- **Buildroot**: `make -C packages/components/buildroot components BOARD=<board>` then `make -C packages/components/buildroot image BOARD=<board>`

### Build Convention

Both targets follow the same two-step pattern via the shared `packages/components/common.mk` (included by both target Makefiles). The packaging scripts (`genassets.sh`, `mkimage.sh`, `mkupdate.sh`) are shared in `packages/image/`, but each target runs them in its own container image — `minime-musl` (Alpine, arm64) or `minime-glibc` (Buildroot, amd64):
```
make components  →  build.sh  (compilation in the target's own container)
make image       →  genassets.sh + mkimage.sh + mkupdate.sh  (shared scripts, target's own container)
```

**Rules:**
- `build.sh` does compilation only. No image packaging (no genimage, no mcopy, no mkdosfs).
- `mkimage.sh` does image packaging only. No compilation (no make, no gcc, no kernel build).
- `mkupdate.sh` does update archive generation only.
- `genassets.sh` does UI asset retrieval and extraction only.
- The Makefile orchestrates the two steps. CI calls `make components` then `make image` separately.
- Never add compilation logic to `mkimage.sh` or `mkupdate.sh`.
- Never add packaging logic to `build.sh`.

## Agent Directives

- **Build Pipeline Trigger Model**: The build pipeline is parameter-driven via **`build.yml`** (`libc`: `alpine` or `buildroot`, `soc`: `rk3566`, `rk3326`, or `h700`, `ui`: `minui`, `muos`, or `allium`) feeding the `testing` release. It triggers on every push to `main` filtered to `minime/**`, `src/**`, `.github/workflows/**` (building the default `alpine / rk3566 / minui`), `workflow_dispatch` (single selected target), and **`nightly.yml`** (daily cron at 04:00 UTC = 07:00 GMT+3 running a 15-target matrix over all valid combinations, excluding `buildroot + h700`). Each run calls the shared **`build-bootloader.yml`** reusable workflow (U-Boot for all three boards, cache-hit cheap). Concurrency is keyed per-target (`minime-build-${{ github.ref }}-${{ libc }}-${{ soc }}-${{ ui }}` with `cancel-in-progress: true`) — **the newest run wins** for the same target; disjoint targets run concurrently.
- **Architecture & Optimization Knowledge**: Store all architectural decisions, filesystem/kernel performance optimizations, and design rationale in Architecture Decision Records under `docs/adr/` (e.g. `docs/adr/0013-storage.md`).
- **No Temporary Workarounds**: Fix local/runner states directly in the environment. Never add temporary configs, scripts, or hooks to build logic.
- **Single Source of Truth (no duplicated docs)**: Documentation in the repo must not duplicate information. For any given fact or workflow, there must be exactly **one** canonical location — be it `AGENTS.md`, an ADR under `docs/adr/`, a standalone markdown file, or the code itself (e.g. `.github/workflows/*.yml`). Before writing or editing docs, `grep` for existing coverage; update the canonical source rather than adding a parallel description elsewhere. When one file must reference another, link to it instead of restating its content. Never reference a file or fact that does not exist (e.g. a named doc that was never created) — if it is needed, create it or point the reference at the real source.
- **Doc Size Limit (5 KB)**: No markdown doc in this repo may exceed **5 KB**.
  When a doc grows past the limit, edit it down without losing important details —
  prefer linking to the canonical source (traits files, code, DTS, other docs)
  over inlining tables or long prose. Each ADR covers exactly **one topic**;
  when a topic is addressed across several ADRs, merge them into a single ADR.
  **`docs/TODO.md` is exempt** — it is a living task list, not a documentation
  file, and may grow freely.
- **Path and Restructuring Integrity**: When moving, renaming, or consolidating files or directories (e.g., board assets, source paths, packages), you MUST perform a repository-wide search (`grep`) for all references to the old paths in both `alpine/` and `buildroot/` directories (including Makefiles, package `.mk` files, configs, scripts, workflow files, and `APKBUILD`s) and update them concurrently.
- **Dual-Distro Co-equality**: Both Alpine and Buildroot are co-equal consumers of the shared assets. When modifying or consolidating a shared config/path, ensure the change is implemented in both build targets, verifying that neither target is left broken or using outdated paths.
- **UI Submodules & CI Artifacts**: `packages/ui/allium`, `packages/ui/minui`, and `packages/ui/muos` are git submodules tracking upstream/fork branches. UI binaries are compiled by the `ui` job in `build.yml` (musl on ARM64, glibc on AMD64 cross) and passed to `build-os` as ephemeral GitHub Actions run artifacts (`ui-{ui}-{libc}`). They are never committed to git and never uploaded to a GitHub Release. At packaging time `genassets.sh` extracts the matching archive from the downloaded artifact into `packages/ui/out/` (ephemeral runner path). Submodule SHAs in `minime` are bumped automatically by `update-submodules.yml` (daily cron + `repository_dispatch`).
- **Minimal UI Codebase Intrusion**: Unless implementing a user-requested feature, restrict UI code modifications strictly to the Minime platform port directory (e.g. `workspace/minime/` in MinUI, `src/platform/minime/` in Allium). Leave shared upstream launcher code untouched. Exceptions are permitted ONLY when:
  - Working around upstream behavior within the platform port directory is excessively complex or hacky (e.g. requiring dozens of lines of workaround vs. a clean one-line fix in shared code).
  - The change objectively fixes crashes, memory/data corruption, thread deadlocks, or performance regressions present in the original codebase.
- **On-Device Live Verification**: After modifying any code and allowing CI to rebuild artifacts, AI agents must deploy and empirically verify changes on the live physical hardware target. Deliver the latest testing OTA with the on-device updater via `just shell "/usr/bin/update.sh [target] [ui]"` (e.g. `just shell "update.sh minui"`, `just shell "update.sh buildroot"` — it self-detects SoC and any omitted target/UI, detaches from the session, and reboots when done), confirm the device is current with `just shell "cat /mnt/sdcard/.minime/manifest.json"`, and use `just shell <cmd>` (or `just shell <cmd>` over SSH — dropbear is enabled by default) for on-device inspection. For a full reflash, use `just deploy <os> <board> <ui> [disk]`. Follow the **`live-test` skill** for the full procedure (deploy, device log locations, and the 5 Whys debugging workflow).

## Device Card Mount (`card`)

`card` at the repo root is a **local symlink to `/Volumes/minime`** — the SD card mounted on this Mac when it is inserted (macOS mounts a FAT volume labeled `minime` there). It is **gitignored** because it is a machine-specific absolute path; never commit it or rely on it being present in a fresh clone. When the card is mounted, read/inspect device logs via `card/` from the repo root (e.g. `card/.minime/logs/<boot-id>/boot.log`, `card/wifi.diagnostics`) — no permissions needed for reads. When unmounted the symlink dangles and those paths fail, which just means the card is not inserted. Reflashing still requires `sudo dd` (raw device write), typically via `just deploy`.

## Infrastructure & Scripts

**Mandatory reading for AI agents**: Before making any changes to build or workflow files, read [`docs/INFRA.md`](docs/INFRA.md) — it documents the full CI pipeline (workflows, scripts, dependencies, caches, and outputs). The `.github/workflows/*.yml` files are the executable source of truth for the pipeline; INFRA.md is the human-readable reference for it.

## Unified Validation Quality Gates

All checks must pass before committing. Do not suppress/bypass warnings.

Validation is **local-only and owned by `scripts/`**: every check lives in a
`scripts/check-*.sh` file and is invoked through `just`. There is **no CI
validation job** — the build pipeline is the functional gate (a broken change
fails at `make components` / `make image`), and `--no-verify` is prohibited
below. The installed hooks are the primary gate; do not treat them as optional.

- **Full gate**: `just validate` (adds UI formatting checks — needs Rust + clang)
- **Fast static gate**: `just validate-static` (no cargo/clang toolchains) — run
  by the `pre-commit`/`pre-push` hooks installed via `just install-hooks`
- **Buildroot-dependent gate**: `just validate-ci` (requires upstream Buildroot tree)
- **Setup (once per clone)**: `mise install` then `just install-hooks`

**`--no-verify` is prohibited.** Never pass `--no-verify` to `git commit` or
`git push`. The hooks exist to stop broken code from being committed at all —
bypassing them defeats the only validation the repo has. There is no CI safety
net underneath. (A `just commit` wrapper that removes the `--no-verify` path
entirely is planned — see `docs/TODO.md`.)


## BIOS ROMs

The `bios/` directory is **not** part of this repository. Console BIOS ROMs used
by the emulator cores live in the private Forgejo repo `jheronimus/console-bios`
(never GitHub). To build a full image locally, check out that repo and place its
contents at `bios/` inside this checkout (it is gitignored).
