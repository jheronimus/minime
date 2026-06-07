# Panfrost Prebuilt Package

Contains precompiled Mesa/LLVM binaries for dynamic GPU driver switching.

## Rebuilding Prebuilts
To compile the precompiled libraries from source using the Buildroot toolchain:
1. Run `make panfrost BOARD=<board>` (default: `h700`).
2. This compiles Mesa and LLVM and outputs a tarball: `out/panfrost-<version>.tar.gz`.

## Updating & Deploying
1. Manually update `PANFROST_VERSION` in [panfrost.mk](file:///Users/ilembitov/Projects/minime/external/package/panfrost/panfrost.mk) (e.g., `25.0.7r3`).
2. Commit and push the changes to trigger the manual GitHub Actions workflow.
3. The workflow will build, package, and upload `panfrost-<version>.tar.gz` to the `minime` GitHub Release assets.

## Dependencies
* System dependencies (`libzstd`, `libffi`, `libxml2`, `libedit`, `libz3`) are NOT packaged in the tarball.
* They are declared in [Config.in](file:///Users/ilembitov/Projects/minime/external/package/panfrost/Config.in) and compiled from source by Buildroot at target image build time.
