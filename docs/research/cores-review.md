# Shared Libretro Core Review (2026-08)

## Context

Minime's shared cores (built from `minime/build/cores/manifest` by `buildcores.sh`,
consumed by MinUI, Allium and muOS) were inherited verbatim from MinUI, whose
`platform=minime` cores target the weakest Anbernic chips (RGB30/RK2023-class).
Adding the muOS frontend port surfaced the need to re-review: muOS/Rocknix/Knulli
all default to more accurate cores, and Minime now covers N64/PSP/Dreamcast-class
hardware (RK3326 A35, H700 A53, RK3566 A55).

## Ecosystem defaults vs. MinUI heritage

| System | Current (MinUI) | muOS | Rocknix | Knulli | Decision |
|---|---|---|---|---|---|
| NES | fceumm | fceumm | nestopia | fceumm | keep fceumm |
| SNES | snes9x2005_plus | snes9x | snes9x | snes9x | **add snes9x, new default** |
| GB/GBC | gambatte | gambatte | gambatte | gambatte | keep |
| GBA | gpsp | mgba | mgba | mgba | mgba default (follow-up) |
| MD | picodrive | genesis_plus_gx | genesis_plus_gx | genesis_plus_gx | **add genesis_plus_gx, new default** |
| SMS/GG | picodrive | smsplus/picodrive | gearsystem | genesis_plus_gx | keep picodrive |
| PS1 | pcsx_rearmed | pcsx_rearmed | pcsx_rearmed | pcsx_rearmed | keep |
| PCE | mednafen_pce_fast | mednafen_pce_fast | beetle_pce_fast | pce_fast | keep |
| NGPC | race | mednafen_ngp | beetle_ngp | mednafen_ngp | **add mednafen_ngp, new default** |
| Lynx | handy | handy | handy | mednafen_lynx | keep |
| WS/VB/PKM | mednafen_* | mednafen_* | beetle_* | mednafen_* | keep |
| P8 | fake08 | fake08 | pico8 (sa) | fake08 | keep (+ glibc P8-NATIVE) |
| A2600 | stella | stella2014 | stella | stella | keep |
| NDS | drastic (WIP) | drastic (sa) | drastic (sa) | desmume/drastic | **WIP, unchanged** |
| Saturn | yabasanshiro (WIP) | yabasanshiro (sa) | yabasanshiro (sa) | yabasanshiro (sa) | **WIP, unchanged** |
| N64 | — | mupen64plus_next | mupen64plus_next | mupen64plus_next | **add mupen64plus_next** |
| PSP | — | ppsspp (sa) | ppsspp (sa) | ppsspp (sa) | **add ppsspp (libretro)** |
| Dreamcast | — | flycastvl | flycast2021 | flycastvl | **add flycast (upstream)** |
| Arcade | — | fbneo | fbneo | fbneo | **add fbneo** |

Consensus picks are unambiguous: full `snes9x`, `genesis_plus_gx`, `mednafen_ngp`,
`mupen64plus_next`. For Dreamcast we chose **upstream flycast** over `flycastvl`
(the muOS/Knulli default) and `flycast2021` (Rocknix): flycastvl is a frozen
2021 batocera fork of the deprecated `libretro/flycast` mirror (unreproducible,
GPL-concern, unmaintained); modern flycast still ships a GLES3 path, which is all
the Mali G31/G52 can offer. muOS uses the standalone PPSSPP; Minime's shared-core
model needs the **libretro ppsspp** core instead.

## Emulator config guidance (muOS / Knulli / Rocknix)

Global RetroArch defaults for these SoCs: `video_smooth=false` (bilinear off),
`video_threaded=true`, `video_vsync=true`, hard gpu sync off, frame delay 0,
runahead/rewind off, `audio_driver=alsathread`, latency 32-64, out rate
44100/48000. Heavy systems pin `governor=performance` (N64/DC/PSP/Saturn/NDS).

Per-core options these firmwares ship (initial `default.cfg`/coredef targets):

- **mupen64plus_next**: dynarec, rdp=gliden64, rsp=hle, ThreadedRenderer=True,
  640x360/320x240, MSAA off, bilinear standard, FrameDuping on.
- **flycast**: 640x480 (1x), threaded rendering on, synchronous rendering off,
  auto-skip disabled, DSP off, alpha sorting per-strip, texupscale off,
  SH4 clock 200, fast GD-ROM loading on.
- **ppsspp**: CPU JIT, 480x272 (1x), frameskip off (auto on weakest), fast
  memory on, software skinning on, spline Low, anisotropy 16x off.
- **fbneo**: Neo Geo BIOS unibios, hiscores on, vertical mode off, 44100 Hz.

## Implementation

- `buildcores.sh` gained a `builder` field (`make`|`cmake`) — flycast/ppsspp
  are CMake-only. CMake entries take `-D` args in `flags`; CC/CXX/AR are passed
  for the glibc amd64→aarch64 cross build; the .so is collected from `build/`.
- Manifest grew 19→25 recipes. GLES3 cores are `optional=1` until proven on CI:
  they need a GL host — Allium RetroArch and muOS Pickles provide one, **MinUI
  minarch does not yet** (ADR 0023 blocker), so no MinUI paks for them.
- ppsspp pinned (`autobump=0`, muOS-proven SHA); flycast/mupen64plus_next/fbneo/
  snes9x/genesis_plus_gx/mednafen_ngp float (`autobump=1`).

## Open items

- CI-verify the three GLES cores (esp. glibc cross GL link) and iterate recipes.
- On-device verification of new cores + configs (live-test skill).
- MinUI: swap SFC→snes9x, MD→genesis_plus_gx, NGP/NGPC→mednafen_ngp paks in the
  MinUI fork; add DC/N64/PSP paks once minarch grows GL (ADR 0023).
- muOS: add ppsspp coredef (Pickles) + arcade assign; optional flycastvl.
- Consider `mednafen_supergrafx` (SuperGrafx) and `mednafen_lynx` (muOS/Knulli
  default for Lynx) as follow-ups.