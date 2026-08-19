# ADR 0030: Mainline Kernel as the Source of Truth

## Status

Accepted

## Context

Minime tracked Rocknix kernel patches and maintained hand-authored device
support (local overlay DTS per device plus a Rocknix patch series) for three
SoC families. As mainline kernel DTS support for Anbernic handhelds matured,
this model duplicated what upstream already ships: local DTS duplicated
mainline panels, and the patch series carried content that mainline had
absorbed. Maintaining forks of device support that mainline owns is wasted
work and a constant rebase burden.

## Decision

Mainline Linux is the gate and the source of truth for device support:

1. **Mainline-gated device registry.** The trait registry
   (`packages/components/boards/<board>/traits/`) only contains devices whose DTS is (or
   derives from one that is) in mainline. Non-mainline devices are dropped
   until upstream lands their DTS — e.g. RG40XX-H/V and RG Cube XX were
   removed because their DTS never landed upstream; they return automatically
   once submitted and merged.
2. **Registry mirrors the DTS cascade.** A trait file's `parent=` mirrors the
   DTS `#include`. Derived devices (e.g. RG28XX = RG35XX Plus body + portrait
   panel) inherit core traits instead of duplicating them and carry a `[dts]`
   section (`base=`, `panel=`, `panel_supply=`/`panel_rotation=` for RK3326)
   describing the overlay to generate.
3. **`traits-gen.sh` owns generation and validation.** `packages/image/
   traits-gen.sh` emits the overlay DTS into the kernel tree at build time
   (Alpine APKBUILD + Buildroot `external.mk` call it), prints the shipped-DTB
   list, and `check` cross-references the registry against the Buildroot DTS
   config. `scripts/check-traits.sh` delegates structural validation to it.
   There are no `dts/` directories anymore.
4. **Self-shrinking patch series.** Every kernel patch is tracked in
   `packages/image/kernel-patch-manifest` with its upstream status. Patches whose
   content is confirmed in mainline (`upstream=master`) are auto-dropped by the
   daily `sync-kernel.yml` on the next kernel bump. The patch series therefore
   shrinks as mainline catches up instead of accumulating.

## Consequences

- Device support lives in one place (the registry); the kernel builds derive
  DTB lists and overlays from it, so "shipped but unreachable" devices cannot
  silently appear.
- Rocknix is no longer a tracked dependency — it remains only a read-only
  reference for one-time quirk harvesting.
- Adding a new device is registry-only (trait file + optional panel blob); see
  `docs/MAP.md` "Adding a new device".
- Dropping devices reduces shipped DTBs, firmware blobs, and config entries
  (Buildroot `h700.config`, `tiny-h700.config`) — done together so validation
  stays green.
- Patch triage is explicit and auditable via the manifest instead of tribal
  knowledge.
- UI parser changes (traits.c/Allium reading the registry schema directly) and
  the H700 device-detection probe remain future work tracked in `docs/TODO.md`.

See also [`docs/traits-system.md`](../traits-system.md) for the full intent,
logic, and audit references, and the `kernel-review` skill for kernel-version
evaluation.