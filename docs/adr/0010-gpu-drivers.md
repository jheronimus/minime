# GPU Driver Stack (Mali Bifrost & Panfrost)

## Problem
ARM Mali Bifrost GPUs (Mali-G31 on H700/RK3326, Mali-G52 on RK3566) require proprietary userspace binary blobs (`libmali`) that match specific kernel driver (`mali-kbase`) ioctl interfaces.

## Solution
Build the out-of-tree `mali-kbase` kernel module (`src/mali-kbase/`) against the active Linux kernel tree and bundle matching `libmali` vendor blobs (`src/libmali/`) into the rootfs. OpenRC `init.d/gpudriver` initializes the GPU device node before launcher startup.

## Examples
- Kernel module source: `src/mali-kbase/`
- Userspace driver blobs: `src/libmali/`
- OpenRC service: `packages/components/boards/common/overlay/etc/init.d/gpudriver`

## See Also
- GPU userspace sources: [`src/libmali/`](../../src/libmali/)
- Kernel driver sources: [`src/mali-kbase/`](../../src/mali-kbase/)
