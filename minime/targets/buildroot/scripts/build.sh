#!/bin/sh
# shellcheck shell=sh disable=SC3043,SC3045
# Minime Buildroot component builder.
#
# Pipeline:
#   1. Merge config fragments for the target board.
#   2. Run Buildroot's full build (kernel, userspace, packages).
#   3. Copy final images to the output directory.
#
# The `image` step (genimage.sh + genupdate.sh) is handled by the Makefile
# and runs on the host, not inside this script.
#
# Environment overrides:
#   BOARD               Target board (rk3566). Required.
#   TOPLEVEL_JLEVEL     Parallel build jobs (default: auto-detected).
#   MINIME_ROOT         Path to the minime repo root.
#   BUILDROOT_ROOT      Path to this directory (minime/targets/buildroot).

set -eu

MINIME_ROOT="${MINIME_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
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
BUILDROOT_OUTPUT_DIR="${HOME}/buildroot-output/${BOARD}"
BUILDROOT_CCACHE_DIR="${HOME}/.buildroot-ccache"
BUILDROOT_DL_DIR="${HOME}/.buildroot-dl"
BUILDROOT_MAKE_ARGS="BR2_EXTERNAL=${BR2_EXTERNAL} O=${BUILDROOT_OUTPUT_DIR} BR2_CCACHE_DIR=${BUILDROOT_CCACHE_DIR} BR2_DL_DIR=${BUILDROOT_DL_DIR} MINIME_ROOT=${MINIME_ROOT} BUILDROOT_ROOT=${BUILDROOT_ROOT}"

LOG_DIR="${BUILDROOT_ROOT}/logs"
mkdir -p "${LOG_DIR}"

#──────────────────────────────────────────────────────────────────────────────
# 1. Merge config fragments (defconfig)
#──────────────────────────────────────────────────────────────────────────────

defconfig() {
	log "merging config fragments for ${BOARD} (${UI})..."
	mkdir -p "${BUILDROOT_OUTPUT_DIR}"
	"${BUILDROOT_DIR}/support/kconfig/merge_config.sh" \
		-O "${BUILDROOT_OUTPUT_DIR}" \
		-m \
		"${BR2_EXTERNAL}/configs/common.config" \
		"${BR2_EXTERNAL}/configs/${BOARD}.config" \
		"${BR2_EXTERNAL}/configs/${UI}.config"
	make -C "${BUILDROOT_DIR}" ${BUILDROOT_MAKE_ARGS} olddefconfig
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Build system components
#──────────────────────────────────────────────────────────────────────────────

build_components() {
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
defconfig) defconfig ;;
shell)
	exec /bin/sh
	;;
*)
	die "unknown subcommand: ${CMD} (use components|defconfig|shell)"
	;;
esac
