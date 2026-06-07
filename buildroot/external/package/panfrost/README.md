# Panfrost Prebuilt Package

Contains precompiled Mesa Panfrost and LLVM runtime files built with the Buildroot toolchain.

Normal image builds only consume the archive. They do not bootstrap Mesa/LLVM when the archive is missing.

## Rebuilding Prebuilts

1. Run `make panfrost BOARD=<board>` (default: `h700`).
2. Upload `out/panfrost-<version>.tar.gz` to the matching GitHub Release:
   `panfrost-v<version>`.
3. If enforcing Buildroot source hashes, compute the archive hash and update
   `panfrost.hash` when the release asset changes.

## Archive Layout

New archives use a sysroot-like layout:

```text
COPYING
licenses/
usr/include/
usr/lib/pkgconfig/
usr/lib/panfrost/
```

The package still accepts the first flat archive layout for existing local caches.

## Dependencies

The archive contains Mesa/LLVM Panfrost runtime files only. Shared system libs such as
`libdrm`, `libzstd`, `libffi`, `libxml2`, `libedit`, and `libz3` are built by Buildroot
and declared in both `Config.in` and `panfrost.mk` for deterministic ordering.
