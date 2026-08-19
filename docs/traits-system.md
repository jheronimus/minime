# Traits System: Intent, Logic, References

Canonical design doc for Minime's device-support system (registry → DTS
generation → runtime emission → UI consumers → patch lifecycle). The decision
is recorded in [ADR 0030](adr/0030-mainline-source-of-truth.md); paths and
layouts live in [MAP.md](MAP.md). This doc is the *how it works* reference.

## Intent

- **Deterministic trait files.** `minime/boards/<board>/traits/` is the single
  source of truth for device support. Every derived artifact — overlay DTS,
  shipped-DTB lists, kernel Makefile entries — is **generated** from the
  registry by `minime/build/traits-gen.sh`. Nothing downstream is hand-authored.
- **Follow the mainline.** A device is supported only if its DTS is in mainline
  Linux, or derives from one that is (`parent=` mirrors the DTS `#include`).
  Non-mainline devices are dropped until upstream lands their DTS (e.g.
  RG40XX-H/V and RG Cube XX). Mainline DTS is the hardware truth; the kernel
  version pin (`tinykernel/APKBUILD` `pkgver`, synced to Buildroot by
  `synckernel.sh`) is the version gate.
- **Not other firmwares.** Rocknix is a **read-only reference**, never a
  dependency: do not copy its patches, DTS, or quirk scripts into the tree.
  Only scalar quirk *values* may be harvested as data (e.g.
  `audio_jack_device_name` from `DEVICE_HEADPHONE_DEV`); provenance is
  recorded in the trait file.
- **Validation is the contract.** `scripts/check-traits.sh` (via
  `traits-gen check`), the consumer-parity guard, and the build pipeline
  (`make components`/`make image`) are the quality gates: drift fails loudly
  instead of shipping silently.

## Logic

1. **Registry** (`minime/boards/<board>/traits/`):
   - `platform.ini` — SoC-wide defaults (screen, CPU/GPU, audio, input, power,
     USB, storage).
   - `devices/<device>.ini` — `[match]` (model/compatible, used by the runtime
     detector), `[device]` (identity + optional `parent=` cascade),
     `[screen]`/`[gpu]`/`[input]`/`[wireless]`/`[power]`/`[usb]`/`[storage]`/
     `[audio]` sections, and `[dts]` **generation metadata** (never emitted at
     runtime; see `init.d/traits`).
2. **`traits-gen.sh`** modes:
   - `check <board>` — schema validation (required keys, `parent=` resolves,
     no self-parent/duplicate matches/obsolete values), every core device
     resolves to a DTB, registry ↔ Buildroot DTS config cross-reference.
   - `overlays <board> <outdir>` — emit overlay DTS for devices with a `[dts]
     base=` section (include base, set compatible/model, panel override +
     `panel_supply`/`panel_rotation` for RK3326).
   - `dtbs <board>` — print shipped-DTB paths (drives the Alpine APKBUILD
     build and package list).
   - `makefile <board>` — RK3326 kernel `dtb-` entries.
3. **Build-time integration** — Alpine `aports/tinykernel/APKBUILD` and
   Buildroot `external/external.mk` both call `traits-gen` into the kernel tree
   (`arch/arm64/boot/dts/{allwinner,rockchip}`). The kernel build applies the
   patch series, then builds `Image` + `$_dtbs`.
4. **Runtime emission** — `minime/boards/common/overlay/etc/init.d/traits`
   merges `platform.ini` → parent chain → device file into
   `/mnt/sdcard/.minime/traits`, stripping `[match]`/`[dts]`/`parent` and
   appending a `# traits-hash` marker. Regeneration only happens when the
   content hash changes.
5. **Consumers** — MinUI `traits.c` and Allium `traits.rs` parse the flat
   merged file; `check-traits.sh` enforces that every emitted key exists in
   both parser tables (consumer-parity guard).
6. **Patch lifecycle** — `minime/build/kernel-patch-manifest` tracks each
   patch's upstream status; `sync-kernel.yml` bumps the kernel daily and
   auto-drops patches marked `upstream=master`.

## References (how to check)

- **Mainline DTS (hardware truth)**, pinned by `tinykernel/APKBUILD`:
  - `arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-*.dts` (rg35xx-2024/-h/-plus/-sp)
  - `arch/arm64/boot/dts/rockchip/rk3326-anbernic-rg351m.dtsi` (base of rg351p/mp)
  - `arch/arm64/boot/dts/rockchip/rk3566-anbernic-*.dts` + `rk3568-anbernic-rg-ds.dts`
- **Registry**: `minime/boards/{h700,rk3326,rk3566}/traits/`
- **Generator/validator**: `minime/build/traits-gen.sh`
- **Runtime emitter**: `minime/boards/common/overlay/etc/init.d/traits`
- **Consumers**: Allium `minime/ui/allium/crates/common/src/platform/minime/traits.rs`;
  MinUI `minime/ui/minui/workspace/minime/platform/traits.c`
- **Validation**: `scripts/check-traits.sh`, `check-kernel-config.sh`,
  `check-firmware.sh`, `check-patches.sh`
- **Patch manifest / auto-drop**: `minime/build/kernel-patch-manifest`,
  `.github/workflows/sync-kernel.yml`
- **ADRs**: 0011 (traits schema), 0012 (H700 detection), 0027 (display
  rotation), 0030 (mainline source of truth)
- **Rocknix (read-only, never copied)**: `projects/ROCKNIX/packages/hardware/
  quirks/devices/<Device>/` + `platforms/<SOC>/`, DTS under
  `projects/ROCKNIX/devices/<SOC>/linux/dts/`

For the kernel-evaluation workflow, use the **`kernel-review`** skill
(`.agents/skills/kernel-review/SKILL.md`).
