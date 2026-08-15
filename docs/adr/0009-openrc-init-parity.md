# ADR 0009: OpenRC Cross-Distro Init Parity & Buildroot SysV Pruning

- **Status**: Accepted
- **Date**: 2026-07-28

---

## Context & Problem Statement

Minime maintains two target distributions: Alpine Linux and Buildroot.

By default, Alpine uses OpenRC, while Buildroot defaults to BusyBox init / SysV init scripts. Supporting two different init systems causes:
1. **Duplicate maintenance**: Every service (Wi-Fi, Bluetooth, logging, traits, UI launcher) must be written and maintained twice.
2. **Behavioral drift**: Service supervision, dependency ordering, and logging semantics differ between BusyBox init and OpenRC.

We needed a single unified init system across both distributions.

## Decision

1. **Standardize on OpenRC for both targets**:
   - Alpine uses OpenRC natively.
   - Buildroot enables OpenRC via `BR2_INIT_OPENRC=y` in [common.config](../../minime/targets/buildroot/external/configs/common.config).

2. **Single source of truth for init services**:
   - All shared service definitions live in [minime/boards/common/overlay/etc/init.d/](../../minime/boards/common/overlay/etc/init.d/).
   - Runlevel bindings live in `minime/boards/common/overlay/etc/runlevels/`.
   - Buildroot applies this directory as a root filesystem overlay (`BR2_ROOTFS_OVERLAY`), and Alpine copies it during rootfs assembly.

3. **Prune Buildroot SysV compatibility scripts in post-build**:
   - Upstream Buildroot packages lack OpenRC service definitions and fall back to installing SysV init scripts (`/etc/init.d/S*`).
   - Buildroot's OpenRC package installs a compatibility bridge (`/etc/init.d/sysv-rcs` and `/etc/runlevels/*/sysv-rcs`) that runs all `/etc/init.d/S*` scripts during OpenRC startup.
   - If left intact, daemons start twice (once via Minime's native OpenRC service and once via `sysv-rcs`).
   - [post-build.sh](../../minime/targets/buildroot/external/scripts/post-build.sh) cleans up all legacy SysV scripts and `sysv-rcs` symlinks before generating `system.erofs`:
     ```sh
     TARGET_INITD="${TARGET_DIR}/etc/init.d"
     TARGET_RUNLEVELS="${TARGET_DIR}/etc/runlevels"
     rm -f "${TARGET_INITD}/S"* "${TARGET_RUNLEVELS}"/*/sysv-rcs "${TARGET_INITD}/sysv-rcs" 2>/dev/null || true
     ```

## Consequences

- **Cross-Distro Parity**: Identical service scripts, runlevels, and boot sequences execute on both Alpine and Buildroot.
- **Single Source of Truth**: New services are added once under `minime/boards/common/overlay/etc/init.d/` and work immediately on both targets.
- **Clean Startup**: Buildroot OpenRC boots only Minime-defined services without duplicate execution from upstream package SysV scripts.
- **Low Maintenance**: Buildroot automatically maintains low-level PID 1 plumbing (`inittab`, OpenRC binaries, kernel filesystem mounts) while Minime supplies high-level services.
