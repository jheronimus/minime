# ADR 0024: MinUI feature port — rewind, Wi-Fi, Bluetooth, Power as surgical additions

## Status
Accepted

## Context
MinUI (the Minime fork at `minime/ui/minui`) needs four features previously
implemented in the throwaway `origin/IMPORT` branch: in-game **rewind** and
standalone **Wi-Fi**, **Bluetooth**, **Power** management. IMPORT implemented
them inside a full codebase rewrite (shared settings framework, job queue,
snapshot model, generic UI widgets) — the "change half of MinUI" churn we
avoid on `main`.

The firmware on `main` differs from what IMPORT targeted: Wi-Fi is
`iwd`/`iwctl` ([ADR 0011](0011-iwd-wifi.md)), not wpa_supplicant; Bluetooth is
a single `/etc/init.d/bluetooth` gated by `config/bluetooth/enabled`; the
toolchain containers ship no libdbus dev headers; `device.sh` + `boot.cmd`
already enforce CPU undervolt from `config/device.cfg`.

[NextUI](https://github.com/LoveRetro/NextUI) (a MinUI fork) shipped the same
features on the same base and is the reference for doing it surgically: a thin
`WIFI_*`/`BT_*` platform API with a generic backend, and rewind as a
self-contained module with a single `run_frame()` hook.

## Decision

Port all four features into current MinUI with the smallest possible change
to existing code, preserving IMPORT/NextUI behavior.

### Rewind — in `minarch.c`
- Port NextUI's `ma_rewind.c` logic (~740 LOC, LZ4 keyframe+delta ring buffer,
  async worker thread) into `minarch.c` as static code. No module split.
- Integrate via NextUI's pattern: config globals (`rewind_cfg_*`), a single
  `run_frame()` wrapper around `core.run()` at both existing call sites (main
  loop + `coreThread`; threaded video preserved), `Rewind_init()` gated until
  after `Core_load` (NextUI #728 crash fix).
- 6 frontend options (Enable, Buffer, Interval, Compression, Compression
  Speed, Audio) + Toggle/Hold Rewind shortcuts, exposed through the existing
  Options/Shortcuts menus.
- Add `serialization_quirks` to the core struct; handle
  `GET_SAVESTATE_CONTEXT` + `SET_SERIALIZATION_QUIRKS`; gate audio while
  rewinding; reset history on save/load/reset. Link `-llz4` (present in both
  toolchains and rootfses).

### Wi-Fi / Bluetooth / Power — self-contained Tool PAKs
- New `workspace/all/settings/` component builds three standalone SDL
  processes (`wifi.elf`, `bt.elf`, `power.elf`), shipped as
  `Tools/minime/{Wi-Fi,Bluetooth,Power}.pak` in **BASE**. Each launches like
  the existing Clock/Input tool paks.
- Backends follow NextUI's shim pattern: a small `WIFI_*`/`BT_*` API
  (`common/wireless.h`) with generic implementations (`common/generic_wifi.c`
  speaking `iwctl`, `common/generic_bt.c` speaking `bluetoothctl`). No
  libdbus, no toolchain changes.
- Persistence: Wi-Fi toggles create/remove `config/wifi/enabled` and start/
  stop the firmware `wifi` service; the service now skips startup unless the
  gate exists or `wifi.cfg` has known networks (existing auto-connect users
  unaffected). Bluetooth uses the existing `bluetooth/enabled` gate.
- Power: reads/writes the policy via the `PWR_*` runtime (below); undervolt
  via `device.sh set undervolt`.

### Power policy enforcement — in `common/api.c`
- Port IMPORT's policy runtime: `PWR_loadPolicy()` at `PWR_init` (reads
  `USERDATA_PATH/power.conf`), `PWR_get/set{*}` for sleep/auto-shutdown/lid/
  power-button behavior, validation/sanitization, and wire sleep timeout /
  lid / power-button / auto-shutdown into `PWR_update` (replacing the
  hardcoded 30 s sleep). The Power PAK only writes files; running minui/
  minarch re-read them at their next `PWR_init` (minui auto-relaunches after
  each PAK exits).

### Shared UI widgets
- Extract the existing `MenuList`/`Menu_options`/`Menu_message` from
  `minarch.c` into `common/menu.c`/`menu.h`, adding a right-aligned `badge`
  field (existing value-rendering path) and optional `on_aux` (X-button)
  callback. Compiled into `minarch.elf` and the PAKs — single source of
  truth, identical look to the in-game menu.
- Port IMPORT's on-screen keyboard (`common/keyboard.c`) for Wi-Fi passphrase
  entry — MinUI had no keyboard widget.

## Consequences
- Positive: four features with behavior parity, no settings-framework churn,
  no toolchain/rootfs changes beyond `-llz4`, no firmware changes beyond the
  small `wifi/enabled` gate.
- Negative: `minarch.c` grows ~900 LOC; the PAKs share UI code but no
  framework, so future settings screens would duplicate widget wiring.
- Verification: on-device live test per AGENTS.md (OTA, manifest check, logs).

## References
- [ADR 0011](0011-iwd-wifi.md) — iwd/wifi service (gate change)
- `minime/ui/minui/workspace/all/settings/`, `common/menu.c|keyboard.c|generic_wifi.c|generic_bt.c|wireless.h`
- `minarch/minarch.c` (rewind + `run_frame`), `common/api.c` (power policy)
- `minime/boards/common/overlay/etc/init.d/wifi` (enable gate)
