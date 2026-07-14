# Prebuilt LLVM package set for Minime/Buildroot

This repository builds reusable Buildroot LLVM package artifacts for Minime.

Artifacts are produced per toolchain flavor and Buildroot release:

```text
https://github.com/minime-os/prebuilt-llvm/releases/download/bootlin-musl-2026.02.3/llvm-r1.tar.xz
https://github.com/minime-os/prebuilt-llvm/releases/download/arm-glibc-2026.02.3/llvm-r1.tar.xz
```

The release tag is `<flavor>-<buildroot-version>`. Rebuilds for the same
Buildroot release are uploaded as new immutable assets (`llvm-r2.tar.xz`,
`llvm-r3.tar.xz`, ...), not by replacing older assets.

Mutable channel manifests point at the promoted revision:

```text
channels/bootlin-musl/2026.02.3/stable.json
channels/arm-glibc/2026.02.3/stable.json
```

## Flavors

- `bootlin-musl`: Buildroot's Bootlin AArch64 musl external toolchain.
- `arm-glibc`: Buildroot's Arm AArch64 glibc external toolchain.

The branches named after these flavors contain the same workflow logic but act
as stable build refs for each toolchain flavor. Buildroot versions are release
inputs, not branches.

## Update policy

The scheduled update job checks only for new Buildroot release tags. It does not
track upstream LLVM, Clang, SPIR-V, Bootlin, or Arm toolchain releases directly;
Buildroot is the source of truth for package versions.

When a new Buildroot release appears, the checker dispatches `r1` builds for both
flavors if their GitHub release tags do not already exist.

## Artifact layout

`llvm-rN.tar.xz` contains:

```text
manifest.json
packages/<buildroot-package>/{host,staging,target}
```

The package set currently includes:

- `host-llvm-cmake`
- `host-llvm`
- `host-clang`
- `host-libclc`
- `host-spirv-headers`
- `host-spirv-tools`
- `host-spirv-llvm-translator`
- `llvm`
- `clang`
- `libclc`
- `spirv-headers`
- `spirv-tools`
- `spirv-llvm-translator`

Minime imports these files into Buildroot's `HOST_DIR`, `STAGING_DIR`, and
`TARGET_DIR` via package override/import logic.

