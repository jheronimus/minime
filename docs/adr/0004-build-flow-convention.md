# ADR 0004: Two-Step Build Convention

## Status

Accepted

## Context

After the monorepo restructure (`21b9d09`), Alpine and Buildroot targets had inconsistent build flows:

- **Alpine**: `make image` ran everything in one container invocation (compilation + packaging).
- **Buildroot**: `make image` ran everything monolithically (defconfig + kernel + userspace + erofs + initramfs + genimage). If genimage failed at the end, the full 40-minute build had to be rerun.

There was no clear separation between compilation and packaging, making it impossible to:
- Retry packaging without recompiling
- Share packaging logic between targets
- Run packaging on the host (where genimage/mtools are available)

## Decision

Both targets follow a two-step build convention:

```
make components  →  build.sh  (compilation in builder container)
make image       →  genassets.sh + mkimage.sh + mkupdate.sh  (packaging in shared packager container)
```

### Responsibilities

| Script | Responsibility | Runs |
|--------|---------------|------|
| `build.sh` | Compilation only (minirootfs, APKs, rootfs, erofs, initramfs) | In builder container |
| `mkimage.sh` | SD card image assembly (FAT32, bootloaders, genimage) | In shared packager container |
| `mkupdate.sh` | Update archive generation | In shared packager container |

### Rules

1. `build.sh` must never call `mkimage.sh` or `mkupdate.sh` or `genassets.sh`.
2. `mkimage.sh` must never contain compilation logic (no make, no gcc, no kernel build).
3. The Makefile orchestrates the two steps. CI calls `make components` then `make image` separately.
4. `build.sh` writes artifacts to `out/<board>/`. `mkimage.sh` reads from `out/<board>/`.

### Benefits

- **Failure recovery**: If packaging fails, only the short packaging step needs to rerun, not the full compilation.
- **Shared packaging**: Both targets use the same `mkimage.sh`/`mkupdate.sh` scripts.
- **No host tooling**: Packaging runs in the shared packager container — no genimage/mtools needed on the host.
- **Clear boundaries**: Each script has a single responsibility.

## Consequences

- Alpine's `build.sh` lost the `all` and `image` subcommands; `components` now includes erofs+initramfs.
- Buildroot's `system-image.sh` no longer calls genimage; that responsibility moved to the shared packager container.
- A new shared packager container (`minime/build/container/Dockerfile`) provides genimage/mtools for both targets.
- CI workflows no longer need host tools (mtools, genimage, u-boot-tools) for the `make image` step.
