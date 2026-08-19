# ADR 0027: Display Rotation Ownership

## Context

Minime's display orientation has been enforced at inconsistent layers per SoC
family, based on the incorrect belief (ADR 0011, `rk3566/boot.env`) that "the
kernel applies the DTS panel `rotation` property so the framebuffer is already
upright." Verification shows that is not true:

- `panel-simple` and the H700 generic panel driver (`h700/patches/linux/0012`)
  both map rotation to `drm_connector_set_panel_orientation()` — a connector
  property documented as a **hint to userspace**, not a scanout rotation. No
  driver rotates the scanout from it.
- The H700 panel init sequences (decoded from the kikuchan98 panel-firmware
  presets, `panels/*.panel`) contain only BGR / scan-direction MADCTL values
  (`0x36 0x0a`), never an actual 90/270 rotation. The panels do **not**
  self-rotate.
- The H700/RK3326 display controllers (Allwinner DE2, Rockchip VOP-lite) expose
  no plane rotation; only RK3566 VOP2 has hardware 90/270 plane rotation.

Consequences of the false belief: the RG28XX/RG351V traits were
`screen_rotation=0` (portrait-mounted panels display sideways), and the H700
panels other than rg35xx-plus shipped **no firmware blob** — the generic driver
requires one at probe, so those panels never initialize. The `remote` tool must
apply an inverse rotation because it reads buffers that the UI already rotated.

## Decision

1. **The trait is the single source of truth** for panel orientation.
   `screen_rotation` is the angle the UI must apply. Consumers (MinUI, Allium,
   muOS, emulators, `remote`) all read it.

2. **Rotation is handled uniformly in userspace/UI.** Because H700 and RK3326
   display controllers (Allwinner DE2, Rockchip VOP-lite) have no hardware
   rotation units, all launchers and emulators rotate their framebuffers directly
   using `screen_rotation`. The experimental `minime-rotate` KMS plane rotation
   tool and `init.d/display` service have been removed.

3. **H700 panel firmware blobs are shipped** for all panels across H700 variants:
   rg28xx, rg34xx, rg34xx-sp, rg35xx-plus-rev6, and rg35xx-sp-v2.
   Without a blob the generic driver fails probe.

4. **Portrait-mounted devices get correct traits**: RG28XX `screen_rotation=270`
   (authoritative from the panel preset). RG351V is set to 90,
   pending on-device confirmation of the exact direction.

## Consequences

- UIs, emulators, and `remote` rotate cleanly via the `screen_rotation` trait.
- H700 display bring-up works for all shipped panels.
- Zero kernel/KMS plane rotation state to manage or distort fbdev dimensions.

## Status

Accepted.
