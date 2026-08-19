# Logging & Remote Diagnostics

## Problem
Handhelds lack persistent serial consoles or desktop display servers, making it difficult to diagnose boot failures, kernel panics, or graphics issues during development.

## Solution
Standardized boot logging (`/usr/share/minime/scripts/log-boot.sh`) logs init milestones to `/mnt/sdcard/.minime/logs/<boot-id>/boot.log`. A diagnostics script packages system status into a tarball. The `remote` CLI tool provides remote execution, live frame buffer screenshots (`remote screenshot`), and key injection over the network.

## Examples
- Pull diagnostics bundle: `just logs`
- Capture device screenshot: `just screenshot`
- Run remote command: `just shell "dmesg | tail -n 20"`

## See Also
- Diagnostics script: [`packages/components/boards/common/scripts/collect-diagnostics.sh`](../../packages/components/boards/common/scripts/collect-diagnostics.sh)
- Remote command utility: [`scripts/remote-cmd.sh`](../../scripts/remote-cmd.sh)
