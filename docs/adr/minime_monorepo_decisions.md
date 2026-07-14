# Minime Monorepo — Architecture Decisions

> Outcome of design session, 2026-07-14.
> Resolves the multi-repo complexity in `minime-os` organisation.

---

## Decision 1 — Consolidate into `jheronimus/minime` (public monorepo)

**From:** `minime-os` organisation with 8+ repos, a metarepo, and per-device git branches.  
**To:** Single **public** monorepo `jheronimus/minime`. `minime-os` org dissolved.

**Migration vehicle:** Migrate all content into `jheronimus/prebuilt-llvm`, then rename it to `jheronimus/minime`. GitHub preserves stars, forks, and redirects on rename — the existing star is preserved.

**Why public:** GitHub Actions is free with no minute cap for public repos. The build content (Buildroot configs, kernel patches, board overlays, GPL driver source) is not sensitive. Private context files are gitignored instead.

**Privacy handling:**
- `AGENTS.md` → added to `.gitignore`; kept locally; a sanitized public `AGENTS.public.md` (no IPs, no machine names) is committed instead
- `.scratch/` → added to `.gitignore`; map-work tickets remain local only
- Local network details (`192.168.1.218`, `htpc.local`) → move to gitignored `local.mk` or `.env`

**Top-level layout:**
```
jheronimus/minime/
  buildroot/          ← Buildroot build system (external/, configs/, Makefile, container/, scripts/, support/)
  alpine/             ← Alpine build system (aports/, board/, scripts/, container/)
  drivers/
    mali-kbase/       ← kernel module source (compiled package)
  docs/
    adr/              ← ADRs
  .github/
    workflows/        ← 6 workflows + llvm-prebuilt
  scripts/
  AGENTS.md
```

---

## Decision 2 — Upstream Buildroot: tarball download, not submodule

**From:** Buildroot as a git submodule (or assumed as such).  
**To:** Downloaded as a tarball at build time, pinned by `BUILDROOT_VERSION` in the Makefile.

**Rationale:** The buildroot branch already implements this correctly (`BUILDROOT_VERSION := 2026.05`, stamp-based download, tarball extraction). No submodule to remove — it's already the right pattern. The downloaded `buildroot/` directory is gitignored.

**One Buildroot patch exists:** `buildroot/support/buildroot-patches/0001-minime-import-prebuilt-llvm-packages.patch`. Applied automatically during bootstrap. Must be preserved in the monorepo.

---

## Decision 3 — Independent Makefiles in Subdirectories

**From:** Unified make script proposed at the root.  
**To:** Keep separate Makefiles directly inside `buildroot/` and `alpine/` directories.

**Rationale:** Preserves the ability to run direct passthrough commands to upstream Buildroot/Alpine without adding complexity or wrapper parameters. Developers just run `cd buildroot && make <target>` or `cd alpine && make <target>`. No top-level Makefile is needed.

---

## Decision 4 — libmali and mali-kbase: into the monorepo, per-device branches collapsed

**From:** Two separate repos (`minime-os/libmali`, `minime-os/mali-kbase`) with per-device git branches (h700, rk3326, rk3566).  
**To:** Both folded into the monorepo; branch differences become directories.

**libmali (binary blobs):**  
Each platform branch contained different `.so` files (different GPU variants). These become board overlay files — installed directly into the rootfs by Buildroot's overlay mechanism:
```
buildroot/external/board/h700/overlay/usr/lib/libmali-bifrost-g31-g24p0-gbm.so
buildroot/external/board/rk3326/overlay/usr/lib/libmali-bifrost-g31-{g13p0,g2p0}-gbm.so
buildroot/external/board/rk3566/overlay/usr/lib/libmali-bifrost-g52-{g13p0,g24p0,g2p0}-gbm.so
```

**mali-kbase (kernel module source):**  
Lives at `drivers/mali-kbase/`. Referenced by a Buildroot package recipe in `buildroot/external/package/mali-kbase/`.

**Unified `libmali` Buildroot package:**  
A single package handles both blob installation and mali-kbase compilation. GPU variant is selected via Kconfig (set in each board's defconfig):
```kconfig
choice
  prompt "Mali GPU variant"
  depends on BR2_PACKAGE_LIBMALI
  config BR2_PACKAGE_LIBMALI_BIFROST_G31_G24P0   # H700
  config BR2_PACKAGE_LIBMALI_BIFROST_G31_G13P0   # RK3326
  config BR2_PACKAGE_LIBMALI_BIFROST_G52_G13P0   # RK3566
  ...
endchoice
```

**Panfrost/libmali mutual exclusion:** `BR2_PACKAGE_LIBMALI` and panfrost are a `choice` or `depends on !` — prevents a device ending up with both a blob and a kernel driver it can't use.

**Alpine:** libmali packages dropped entirely. libmali is glibc-based and incompatible with musl. Alpine devices use panfrost only.

---

## Decision 5 — Dead repos: deleted

The following repos are deleted, not archived. All were unfinished:
- `minime-os/arch`
- `minime-os/4in1`
- `minime-os/test-roms` (mednafen-based accuracy test ROMs; folded into `eros` repo)
- `mednafen` directory in metarepo

---

## Decision 6 — roms: into the monorepo

`minime-os/roms` (public-domain ROMs used for testing) folds into the monorepo as a plain directory. It is a package in both Buildroot and Alpine.

---

## Decision 7 — prebuilt-llvm: into the monorepo (as the migration vehicle)

`minime-os/prebuilt-llvm` content folds into `jheronimus/minime` as `buildroot/prebuilt-llvm/`.

**Migration approach:** All monorepo content is migrated into the existing `jheronimus/prebuilt-llvm` repo, which is then **renamed to `jheronimus/minime`**. GitHub preserves the existing star, any forks, and sets up URL redirects automatically.

**Rationale:** Keeps it in the monorepo for the 3-stage CI pipeline (`needs:` chain), shares the dl/ cache, and uses the same workflow infrastructure. Bonus: preserves the star.

---

## Decision 8 — minui and allium: proper forks on jheronimus

**From:** `minime-os/minui` and `minime-os/allium` — heavily modified forks with Minime-specific changes accumulated on top of old upstream snapshots. Not in the monorepo (separate submodules).

**To:** Two standalone public forks under `jheronimus`, structured as proper upstreams. The monorepo references their pre-built binary artifacts via package recipes, not their source.

### jheronimus/minui

- Fork from upstream MinUI
- Current `minime-os/minui` code → pushed to `IMPORT` branch for reference and cherry-picking
- All original MinUI platforms → moved to `deprecated/` (NextUI-style)
- New first-class `minime` target built from scratch (6 months of active development)
- Other active MinUI forks (NextUI, etc.) retain compatible structure for cherry-picking

### jheronimus/allium

- Fork from upstream Allium (active project; Miyoo Mini focus)
- Current `minime-os/allium` code → pushed to `IMPORT` branch
- Upstream Miyoo Mini support **preserved and kept in sync** with upstream
- `minime` added as a new platform target alongside `miyoo`: separate Cargo feature (`--features=minime`) and platform crate
- All Minime-specific code isolated behind `#[cfg(feature = "minime")]` — no exceptions — to keep upstream merges clean

### Build model (ownership inversion)

UI repos own their binary build. Minime owns image assembly.

```
jheronimus/minui CI   → aarch64 binary → GitHub release artifact
jheronimus/allium CI  → aarch64 binary → GitHub release artifact
                                ↓
Minime Buildroot/Alpine package → downloads pinned release artifact
                                ↓
Minime CI → assembles flashable image
```

UI repos have their own release cadence and versioning. Minime package recipes pin to a specific release tag.

**Why not build images in the UI repos:** Producing a flashable image for H700/RK3326/RK3566 requires U-Boot, kernel, genimage partition layout — none of which belong in a UI project. The inversion is in *ownership and versioning*, not in who runs `genimage`.

---

## Decision 9 — CI: Consolidated workflows, all on `ubuntu-latest`

**From:** Buildroot and Alpine workflows split across separate individual files, some targeting self-hosted runners.

**To:** All workflows on `runs-on: ubuntu-latest`.

### Buildroot: Consolidated Workflow (`buildroot.yml`)

Consolidates all board builds (`h700`, `rk3326`, `rk3566`) into a single workflow file.

```
Job 1: shared-sources
  trigger: any buildroot/** change
  runs:    make source sequentially for h700/rk3326/rk3566
  output:  warm dl/ cache
           ↓ needs:
Job 2a: build-h700   ─┐
Job 2b: build-rk3326 ├─ parallel, restore shared dl/ cache, build board image
Job 2c: build-rk3566 ─┘
```

**Cache split:**
- `dl/` — shared cache key across all boards (`buildroot/Makefile` hash); same tarballs for every board
- `ccache` — board-specific cache key; different compiler flags per board

### Alpine: Single Workflow (`alpine.yml`)

Alpine currently only supports `rk3566` (no other boards exist in the Alpine tree). It is configured under a single `alpine.yml` workflow.

Registers QEMU using `docker/setup-qemu-action@v3` before launching the `--platform linux/arm64` container to compile on GitHub-hosted runners.

**Cache split (Alpine):**
- `/alpine-dl` — shared key across boards; same source tarballs
- `/alpine-ccache` — board-specific
- `/alpine-repos` — shared APK repository cache

---

## Migration Sequence

1. Create `jheronimus/minime` private monorepo from current `minime-os/minime` buildroot branch as base
2. Merge alpine branch content into `alpine/` directory; buildroot content into `buildroot/`
3. Fold in `roms`, `mali-kbase`, `libmali` blobs into monorepo directories
4. Build unified Makefile and unified `libmali` Buildroot package
5. Create `jheronimus/minui` from upstream MinUI; push current work as `IMPORT` branch
6. Create `jheronimus/allium` from upstream Allium; push current work as `IMPORT` branch
7. Add Alpine CI workflows (all 6) targeting `ubuntu-latest`; validate all builds pass
8. Move `prebuilt-llvm` to `jheronimus/prebuilt-llvm`
9. Delete dead repos: `arch`, `4in1`, `test-roms`, `mednafen`
10. Dissolve `minime-os` org
