# MAP: Shared — Single Source of Truth

Files where one canonical copy serves both Alpine and Buildroot.

## Already unified via `src/`

| Dir | Source of truth | Alpine consumer | Buildroot consumer |
|---|---|---|---|
| `src/bootsplash/` | `src/bootsplash/` | `alpine/aports/bootsplash/APKBUILD` → `../../../src/bootsplash/` | `package/bootsplash/bootsplash.mk` → `$(BR2_EXTERNAL)/../../src/bootsplash` |
| `src/libmali/` | `src/libmali/` | — | `package/libmali/libmali.mk` |
| `src/mali-kbase/` | `src/mali-kbase/` | — | `package/mali-kbase/mali-kbase.mk` |

## Traits (`platform.ini` + device `.inis`)

Buildroot's `board/common/post-build.sh` copies traits directly from
`alpine/board/{h700,rk3326,rk3566}/traits/`. **Source of truth: Alpine tree.**

## Boot scripts (`boot.cmd`) + DTS overlays

Buildroot's `board/common/post-build.sh` compiles `boot.cmd` into `boot.scr`
via mkimage. Both post-image scripts reference DTS overlays from
`alpine/board/rk3566/overlays/`. **Source of truth: Alpine tree.**

## `config/cores.cfg`

| Alpine | Buildroot |
|---|---|
| `alpine/board/common/config/cores.cfg` | `buildroot/external/board/common/config/cores.cfg` |

**Identical content.** Touching one without the other creates drift.
Should be unified (e.g. `src/cores.cfg` or single authoritative copy).

## `usr/bin/autologin`

| Alpine | Buildroot |
|---|---|
| `alpine/aports/minime-overlay/files/usr/bin/autologin` | `buildroot/external/board/common/overlay/usr/bin/autologin` |

**Nearly identical** (Alpine adds one comment line). Trivial to unify.

## Board firmware blobs

All firmware consolidated under `alpine/board/*/firmware/`. Buildroot
references it from there. See MAP_BINARIES.md for the full inventory.

- `alpine/board/common/firmware/` — Common Realtek Wi-Fi/BT (rtl_bt, rtw88)
- `alpine/board/h700/firmware/panels/` — H700 MIPI DPI panel init
- `alpine/board/rk3326/firmware/` — RK3326 USB dongle Wi-Fi/BT drivers

## U-Boot configs (`uboot.config`)

Source of truth is `alpine/board/*/uboot.config`. Buildroot CI references
these via bootloader defconfigs. Already single source.

## Genimage configs

Source of truth is `alpine/board/`. Buildroot uses the same files (passed
via `-c`). Already single source.
