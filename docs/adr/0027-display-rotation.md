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

Consequences of the false belief: the RG28XX/RG40XX-V/RG351V traits were
`screen_rotation=0` (portrait-mounted panels display sideways), and the H700
panels other than rg35xx-plus shipped **no firmware blob** — the generic driver
requires one at probe, so those panels never initialize. The `remote` tool must
apply an inverse rotation because it reads buffers that the UI already rotated.

## Decision

1. **The trait remains the single source of truth** for panel orientation.
   `screen_rotation` is the angle the UI must apply. Consumers (MinUI, Allium,
   `remote`, `minime-rotate`) all read it.

2. **A shared `init.d/display` overlay service** (plus `/usr/bin/minime-rotate`)
   owns rotation that Minime applies outside the UI. It reads the optional
   `screen_rotation_kernel` trait; when set and non-zero it programs the VOP2
   primary-plane `rotation` property on the internal (non-HDMI) connector before
   the UI starts. On H700/RK3326 it no-ops (no rotation silicon) and only
   reports the enforcement layer.

3. **H700 panel firmware blobs are shipped** for every panel the panel-firmware-generator presets cover: rg28xx, rg34xx, rg35xx-plus-rev6, rg40xx, rgcubexx (validated byte-for-byte against the existing rg35xx-plus blob). Without a blob the generic driver fails probe. The **v2/sp panel variants** (rg34xx-sp, rg35xx-sp-v2, rg40xx-v2) have **no published presets** and remain uninitialized until their init sequences are sourced (tracked in TODO).

4. **Portrait-mounted devices get correct traits**: RG28XX `screen_rotation=270`
   (authoritative from the panel preset). RG40XX-V and RG351V are set to 90,
   pending on-device confirmation of the exact direction.

5. **`screen_rotation_kernel` is NOT enabled anywhere yet.** Enabling it for an
   RK3566 device requires the UI rotation to be dropped (`screen_rotation=0`) and
   the fbdev path verified: the fbdev framebuffer is allocated at native mode
   dimensions, so 90/270 plane rotation of it distorts (a known mainline fbdev
   TODO). KMS clients (SDL) control buffer dimensions and work; Allium (fbdev)
   does not until the fbdev emulation reports logical dimensions. This is the
   on-device verification task.

## Consequences

- UIs/emulators/`remote` keep rotating via the trait until a device opts into
  `screen_rotation_kernel`; `remote` then stops rotating automatically because
  it reads the trait (`screen_rotation` becomes 0).
- H700 display bring-up now works for all shipped panels.
- Portrait devices are no longer silently sideways; exact angles are confirmed
  with `remote screenshot --raw` (`remote-diagnostics` skill recipe 3).
- Verification steps are tracked in `docs/TODO.md` ("Display, Audio & Input").

## Status

Accepted.
