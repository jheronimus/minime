# Power Management, Thermals & Charging

## Problem
Handheld gaming devices in compact plastic enclosures risk thermal throttling or battery drain if CPU governors, PMICs, and charging states are unmanaged.

## Solution
Tuning CPU frequency governors (`schedutil` / `performance`) per board, enforcing thermal trip points in Device Trees, preventing RSB/I2C bus lockups on AXP PMIC access, and detecting charger-triggered cold boot to enter low-power charging mode when powered without user intervention.

## Examples
- Charger boot detection: `packages/components/boards/common/overlay/usr/bin/update.sh`
- Thermal trip points: `packages/components/boards/h700/` and `packages/components/boards/rk3566/`

## See Also
- Board patches: [`packages/components/boards/`](../../packages/components/boards/)
