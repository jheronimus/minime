#!/bin/sh
# shellcheck shell=sh disable=SC3043,SC3045
# Minime Buildroot component builder.
#
# Pipeline:
#   1. Merge config fragments for the target board.
#   2. Run Buildroot's full build (kernel, userspace, packages).
#   3. Copy final images to the output directory.
#
# The `image` step (genassets.sh + mkimage.sh + mkupdate.sh) is handled by the Makefile
# and runs on the host, not inside this script.
#
# Environment overrides:
#   BOARD               Target board (rk3566). Required.
#   TOPLEVEL_JLEVEL     Parallel build jobs (default: auto-detected).
#   MINIME_ROOT         Path to the minime repo root.
#   BUILDROOT_ROOT      Path to this directory (minime/targets/buildroot).

set -eu

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
BUILDROOT_ROOT="${BUILDROOT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

BOARD="${BOARD:-rk3566}"
TOPLEVEL_JLEVEL="${TOPLEVEL_JLEVEL:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
UI="${UI:-minui}"

log() { printf '[buildroot] %s\n' "$*" >&2; }
die() {
	log "ERROR: $*"
	exit 1
}

case "${BOARD}" in
rk3566 | rk3326 | h700) ;;
*) die "unsupported BOARD=${BOARD} (supported: rk3566, rk3326, h700)" ;;
esac

# Resolve paths
BUILDROOT_DIR="${BUILDROOT_ROOT}/buildroot"
BR2_EXTERNAL="${BUILDROOT_ROOT}/external"
# Overridable so CI container jobs can redirect caches under the workspace
# (persisted by actions/cache); local podman builds use $HOME.
BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-${HOME}/buildroot-output/${BOARD}}"
BUILDROOT_CCACHE_DIR="${BUILDROOT_CCACHE_DIR:-${HOME}/.buildroot-ccache}"
BUILDROOT_DL_DIR="${BUILDROOT_DL_DIR:-${HOME}/.buildroot-dl}"
BUILDROOT_MAKE_ARGS="BR2_EXTERNAL=${BR2_EXTERNAL} O=${BUILDROOT_OUTPUT_DIR} BR2_CCACHE_DIR=${BUILDROOT_CCACHE_DIR} BR2_DL_DIR=${BUILDROOT_DL_DIR} MINIME_ROOT=${MINIME_ROOT} BUILDROOT_ROOT=${BUILDROOT_ROOT}"

LOG_DIR="${BUILDROOT_ROOT}/logs"
mkdir -p "${LOG_DIR}"

#──────────────────────────────────────────────────────────────────────────────
# 0. Ensure Buildroot source is present
#──────────────────────────────────────────────────────────────────────────────

BUILDROOT_VERSION="2026.05.1"
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"

ensure_buildroot() {
	if [ -d "${BUILDROOT_DIR}" ]; then
		log "Buildroot ${BUILDROOT_VERSION} already present in ${BUILDROOT_DIR}"
		return
	fi
	log "Downloading Buildroot ${BUILDROOT_VERSION}..."
	mkdir -p "${BUILDROOT_DIR}"
	curl -fL -o /tmp/buildroot.tar.gz "${BUILDROOT_URL}"
	tar xf /tmp/buildroot.tar.gz --strip-components=1 -C "${BUILDROOT_DIR}"
	rm -f /tmp/buildroot.tar.gz
	if [ -d "${BUILDROOT_ROOT}/support/buildroot-patches" ]; then
		log "Applying Buildroot patches..."
		for p in "${BUILDROOT_ROOT}/support/buildroot-patches/"*.patch; do
			[ -e "$p" ] || continue
			patch -p1 -d "${BUILDROOT_DIR}" <"$p"
		done
	fi
}

#──────────────────────────────────────────────────────────────────────────────
# 1. Merge config fragments (defconfig)
#──────────────────────────────────────────────────────────────────────────────

defconfig() {
	log "merging config fragments for ${BOARD} (${UI})..."
	mkdir -p "${BUILDROOT_OUTPUT_DIR}"
	configs="${BR2_EXTERNAL}/configs/common.config ${BR2_EXTERNAL}/configs/${BOARD}.config"
	if [ -n "${UI}" ] && [ -f "${BR2_EXTERNAL}/configs/${UI}.config" ]; then
		configs="${configs} ${BR2_EXTERNAL}/configs/${UI}.config"
	fi
	"${BUILDROOT_DIR}/support/kconfig/merge_config.sh" \
		-O "${BUILDROOT_OUTPUT_DIR}" \
		-m \
		${configs}
	make -C "${BUILDROOT_DIR}" ${BUILDROOT_MAKE_ARGS} olddefconfig
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Build system components
#──────────────────────────────────────────────────────────────────────────────

build_components() {
	ensure_buildroot
	defconfig
	log "building Buildroot for ${BOARD} (${UI}) with ${TOPLEVEL_JLEVEL} jobs..."
	make -C "${BUILDROOT_DIR}" ${BUILDROOT_MAKE_ARGS} -j"${TOPLEVEL_JLEVEL}"
}

#──────────────────────────────────────────────────────────────────────────────
# 3. Copy images to output directory
#──────────────────────────────────────────────────────────────────────────────

copy_images() {
	TARGET_OUT="${BUILDROOT_ROOT}/out/${BOARD}"
	mkdir -p "${TARGET_OUT}"
	if [ -d "${BUILDROOT_OUTPUT_DIR}/images" ]; then
		cp -r "${BUILDROOT_OUTPUT_DIR}/images/"* "${TARGET_OUT}/" 2>/dev/null || true
	fi
	log "images copied to ${TARGET_OUT}"
}

#──────────────────────────────────────────────────────────────────────────────
# Entrypoint
#──────────────────────────────────────────────────────────────────────────────

CMD="${1:-components}"
case "${CMD}" in
components)
	build_components
	copy_images
	;;
defconfig)
	ensure_buildroot
	defconfig
	;;
source)
	ensure_buildroot
	defconfig
	make -C "${BUILDROOT_DIR}" ${BUILDROOT_MAKE_ARGS} source
	;;
shell)
	exec /bin/sh
	;;
*)
	die "unknown subcommand: ${CMD} (use components|defconfig|source|shell)"
	;;
esac
