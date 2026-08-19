# Dual-Distro Architecture (musl + glibc)

## Problem
Different software ecosystems on embedded gaming handhelds require different C standard libraries. Lightweight, fast-to-compile environments benefit from musl (Alpine), whereas closed-source binaries (e.g. DraStic, proprietary GPU blobs, Pico-8) require glibc (Buildroot). Maintaining separate forks for each distribution leads to severe drift, duplicate patch sets, and redundant configuration files.

## Solution
Minime maintains Alpine (`musl`, `arm64`) and Buildroot (`glibc`, `amd64` cross-compiled) as co-equal target distributions. Common board definitions, kernel patches, OpenRC services, device traits, and image packaging scripts live in a single central location under `packages/components/boards/` and `packages/image/`. Both build targets consume these assets identically.

## Examples
- Alpine build: `make -C packages/components/alpine components BOARD=rk3566`
- Buildroot build: `make -C packages/components/buildroot components BOARD=rk3566`

## See Also
- Central board assets: [`packages/components/boards/`](../../packages/components/boards/)
- Shared container rules: [`packages/components/common.mk`](../../packages/components/common.mk)
- Monorepo guidelines: [`AGENTS.md`](../../AGENTS.md)
