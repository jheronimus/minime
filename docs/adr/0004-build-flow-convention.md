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
make components  →  build.sh  (compilation in container)
make image       →  genimage.sh + genupdate.sh  (packaging on host)
```

### Responsibilities

| Script | Responsibility | Runs |
|--------|---------------|------|
| `build.sh` | Compilation only (minirootfs, APKs, rootfs, erofs, initramfs) | In container |
| `genimage.sh` | SD card image assembly (FAT32, bootloaders, genimage) | On host |
| `genupdate.sh` | Update archive generation | On host |

### Rules

1. `build.sh` must never call `genimage.sh` or `genupdate.sh`.
2. `genimage.sh` must never contain compilation logic (no make, no gcc, no kernel build).
3. The Makefile orchestrates the two steps. CI calls `make components` then `make image` separately.
4. `build.sh` writes artifacts to `out/<board>/`. `genimage.sh` reads from `out/<board>/`.

### Benefits

- **Failure recovery**: If genimage fails, only the 2-minute packaging step needs to rerun, not the full compilation.
- **Shared packaging**: Both targets use the same `genimage.sh`/`genupdate.sh` scripts.
- **Host execution**: Packaging runs on the host where genimage/mtools are available, no container needed.
- **Clear boundaries**: Each script has a single responsibility.

## Consequences

- Alpine's `build.sh` lost the `all` and `image` subcommands; `components` now includes erofs+initramfs.
- Buildroot's `post-image.sh` no longer calls genimage.sh; that responsibility moved to the Makefile.
- CI workflows need host tools (mtools, genimage, u-boot-tools) installed for the `make image` step.
- New `minime/targets/buildroot/scripts/build.sh` wraps Buildroot's build system.
