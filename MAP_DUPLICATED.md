# MAP: Duplicated — Merge Candidates

Files in both trees that should be consolidated to prevent drift.
Merge into a shared script with firmware-specific parameters.

## `post-image.sh`

| Alpine | Buildroot |
|---|---|
| `alpine/board/common/post-image.sh` (485 lines) | `buildroot/external/board/common/post-image.sh` (~380 lines) |

**~90% identical.** One of the highest-value merge targets in the repo.

Same pipeline in both:
1. Extract `rootfs.tar` → `system.erofs`
2. Stage FAT32 userdata partition (bios/, roms/, saves/, .minime/, .ui/, .cores/)
3. Prepopulate `device.cfg` with DTB list + undervolt option
4. Compile DTS overlays → DTBOs
5. Assemble initramfs (busybox + parted + fatresize)
6. Create `userdata.vfat` via mtools
7. Run genimage → trim → gzip

**Differences:**

| Aspect | Alpine | Buildroot |
|---|---|---|
| Path var | `MINIME_SOURCE_ROOT` | `BR2_EXTERNAL_MINIME_PATH` |
| Image tag | `minime-alpine-${SOC_NAME}` (from board.env) | `minime-${SOC_NAME}` (hardcoded) |
| Bootloader staging | Not in post-image | Copies from `alpine/bootloader/${SOC_NAME}/` |
| userdata.vfat size | 1040M | 2048M |
| Distro guard | Rejects non-alpine | None |

**Merge:** Extract common flow into `scripts/post-image-common.sh` with
parameters for image tag prefix, bootloader source path, fat size, and
distro name. Each tree's post-image.sh becomes a thin wrapper.

## `post-build.sh`

| Alpine | Buildroot |
|---|---|
| No script. Overlay files bundled in `minime-overlay` APKBUILD. | `buildroot/external/board/common/post-build.sh` (114 lines) + per-board hooks |

Buildroot's common post-build does:
1. Compile `boot.cmd` → `boot.scr` (from Alpine tree)
2. Add Mali CMA udev rule
3. Create `modules-load.d/wifi.conf`
4. Create `modprobe.d/rtw88.conf`
5. Symlink `/tmp/resolv.conf`
6. Create `/mnt/sdcard` mount point
7. Install common firmware blobs
8. Install traits (from Alpine tree)
9. Run per-board hook if present

Alpine handles these via overlay files in `minime-overlay/files/`. The
overlay files (`wifi.conf`, `rtw88.conf`, etc.) serve the same purpose
with the same content. No shared script exists; drift is possible.

**Options:**
- Keep as-is: overlay approach simpler for Alpine, post-build script
  more flexible for Buildroot.
- Shared generation: a script at `scripts/gen-system-config.sh` that both
  pipelines call, producing identical runtime configs.
