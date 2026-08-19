---
name: kernel-review
description: Evaluate a new kernel version for Minime — determine which new Anbernic devices mainline added, which of Minime's kernel patches can be dropped as their content lands upstream, which patches are needed for newly-added devices, and implement new device support in the traits registry. Use when a kernel version bump is proposed or merged (synckernel.sh / sync-kernel.yml), when checking "what's new in kernel <version>", or when adding support for a new Anbernic handheld. Triggers: "new kernel", "kernel bump", "evaluate new devices", "what's new in 7.x", "add support for <device>".
---

# Kernel Version Review

Evaluating a kernel bump against Minime's device-support system. The design
(intent, logic, references) is documented in
[`docs/traits/TRAITS.md`](../../../docs/traits/TRAITS.md) and the governing
decision in [`docs/adr/0030-mainline-source-of-truth.md`](../../../docs/adr/0030-mainline-source-of-truth.md).
Read those first.

## Core rules

- **Mainline is the gate.** A device ships only if its DTS is (or derives
  from) mainline. Minime's own patches exist to fill gaps mainline has not
  merged yet — they shrink as upstream catches up.
- **Rocknix is read-only reference, never a source to copy from.** Do not
  import its patches, DTS, or quirk scripts. Only scalar quirk *values* may be
  harvested as data (with provenance noted in the trait file).
- **Every patch is tracked.** `packages/components/scripts/kernel-patch-manifest` records
  each patch's upstream status; `sync-kernel.yml` auto-drops patches marked
  `upstream=master`. A kernel review updates this manifest.
- **Registry is the single source of truth.** After any device change, run
  `just validate-static` (traits-gen check + consumer-parity guard) and
  verify with `traits-gen dtbs <board>` / `overlays <board> <dir>`.

## Workflow

### 1. Check what new devices mainline added

Diff the Anbernic DTS between the pinned kernel (see `tinykernel/APKBUILD`
`pkgver`) and the target kernel:

- `arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-*.dts` (H700)
- `arch/arm64/boot/dts/rockchip/rk3326-anbernic-*.dts*` (RK3326)
- `arch/arm64/boot/dts/rockchip/rk3566*-anbernic-*.dts*` (RK3566)

For each new/renamed DTS, map it to a Minime `device_id` and decide whether it
fits the registry (new core device, or a derived device via `parent=`).
Devices previously dropped for lack of upstream DTS (e.g. rg40xx-h/v,
rgcubexx) return automatically once their DTS lands — add them back here.

### 2. Check what patches can be dropped for already-supported devices

For each patch in `packages/components/scripts/kernel-patch-manifest`, check whether its
content is now present in the target kernel:

- Driver patches (e.g. `panel-mipi-dpi-spi`, btrtl chip entries): grep the
  target kernel source for the added symbols/compat strings.
- DTS patches: grep the target kernel's Anbernic DTS for the added nodes /
  properties.

If present, set `upstream=<version>` in the manifest (or `upstream=master` if
only confirmed in master). Patches marked `upstream=master` are auto-dropped
by `sync-kernel.yml` on the next bump; for a manual bump, drop them yourself
with `git rm` and remove their manifest sections. Update any affected config
fragments (`tiny-*.config`, Buildroot configs) if the patch previously enabled
a now-default symbol.

### 3. Check what patches need to be added for new devices

Only add a patch if the new device's DTS or a required driver is genuinely
missing from mainline. Prefer upstream; do NOT port Rocknix patches. A needed
patch should:

- Live in `packages/components/boards/<board>/patches/linux/`, named `NNNN-<slug>.patch`
  following the existing series.
- Get a section in `packages/components/scripts/kernel-patch-manifest` with `upstream=-`
  (record the upstream submission/commit it tracks, if any, in the patch
  header or manifest note).
- Be verified to apply cleanly under Buildroot's strict `--fuzz=0`
  (see the patch READMEs' "Manual Corrections" precedent).

### 4. Implement in traits

Add the device to `packages/components/boards/<board>/traits/devices/<device>.ini`:

- **Mainline DTS used as-is** (identity-only device): set `[match]` +
  `[device]` + full core schema, and `[dts] dtb=<path>` if the DTB name is
  non-obvious (`rk3568-anbernic-rg-ds`); omit `[dts]` to rely on the default
  derivation.
- **Derived device** (new panel / variant of an existing board): add
  `parent=<base>` plus a `[dts]` section with `base=`, `panel=`, and
  `panel_supply=`/`panel_rotation=` for RK3326. traits-gen emits the overlay
  DTS at build time.
- **No DTB of its own** (boots another device's DTB): set `[dts] dtb=none`.

Then, in lockstep:

- Add any new panel firmware blob to `packages/components/boards/h700/firmware/panels/`
  and its `CONFIG_EXTRA_FIRMWARE` entry in `tiny-h700.config`; for Buildroot,
  add the DTB to `external/configs/h700.config`.
- Harvest any known quirks for the new device from the Rocknix quirk scripts
  (`projects/ROCKNIX/packages/hardware/quirks/devices/<Device>/`) — scalar
  values only, provenance noted.
- Run `just validate-static` and confirm `traits-gen dtbs <board>` lists the
  expected DTB(s). Commit; push triggers the CI build.

## Verification checklist

- [ ] `just validate-static` passes (traits-gen check + consumer parity).
- [ ] `traits-gen dtbs <board>` / `overlays <board> <tmpdir>` output matches
      expectations.
- [ ] Kernel builds (`make -C packages/components/alpine components BOARD=<board>`).
- [ ] Manifest entries added/updated for every patch touched.
- [ ] No Rocknix content copied into the tree.
- [ ] On-device verification per the `live-test` skill once CI artifacts land.