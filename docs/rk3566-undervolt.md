# RK3566 CPU Undervolt

Opt-in CPU core undervolt for RK3566 devices, applied at boot via device-tree
overlays. Lowers the voltage requested at each CPU operating point (OPP) to
reduce power draw and temperatures. Based on the ROCKNIX undervolt DTBOs and
the power profiling in [this gist](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7).

## Scope

CPU undervolt only. GPU undervolt and DMC/devfreq tuning are tracked separately.

## Enabling

Edit `.minime/config/device.cfg` on the FAT32 boot partition and set:

```
undervolt=l1
```

Allowed values:

| Value | Description |
|-------|-------------|
| `off` | Stock voltages. |
| `l1`  | Conservative (default). |
| `l2`  | Moderate. |
| `l3`  | Most aggressive. Largest savings, highest instability risk. |

Reboot after changing the value. The selected `.dtbo` is applied by U-Boot
before the kernel boots. On RK3566 the level can also be changed from the
UI Power settings ("CPU Undervolt"); the change is written to this file and
applies on the next boot.

## Recovery

If a level is too aggressive for your silicon the device may fail to boot or
corrupt data. To recover:

1. Eject the SD card and mount the FAT32 partition on a PC.
2. Edit `.minime/config/device.cfg`.
3. Set `undervolt=off`.
4. Reinsert and boot.

## Voltage table

`opp-microvolt` is written as `<target target 1150000>` (target µV, min µV,
max µV). Values in mV:

| CPU MHz | Stock | L1  | L2  | L3  |
|--------:|------:|----:|----:|----:|
| 408     | 825   | 800 | 775 | 760 |
| 600     | 825   | 800 | 800 | 775 |
| 816     | 825   | 800 | 800 | 790 |
| 1104    | 825   | 800 | 800 | 800 |
| 1416    | 900   | 850 | 850 | 825 |
| 1608    | 950   | 900 | 900 | 850 |
| 1800    | 1050  | 950 | 925 | 875 |
| 1992    | 1150  | 1000| 950 | 900 |

## Silicon lottery warning

Undervolt tolerance varies per chip. A voltage marginally below the stability
threshold causes data corruption, not just crashes. Default is `off`, matching
ROCKNIX. Opt in via the Power settings menu ("CPU Undervolt") or by editing
`.minime/config/device.cfg`. L3 matches the measured savings from the
reference profiling but is the most likely to fail on marginal silicon. Start
at `l1` and only increase if stable under a sustained load test.

## How it works

- `minime/external/board/rk3566/overlays/rk3566-undervolt-cpu-l{1,2,3}.dts`
  are compiled to `.dtbo` by `post-image.sh` and staged under
  `.minime/overlays/` on the boot partition.
- `boot.cmd` reads `undervolt` from `.minime/config/device.cfg` and, if set to
  `l1`/`l2`/`l3`, loads and applies the matching overlay with `fdt apply`
  before booting the kernel.
- U-Boot is built with `CONFIG_OF_LIBFDT_OVERLAY=y` and `CONFIG_CMD_FDT=y`.
