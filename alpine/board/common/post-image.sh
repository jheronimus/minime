#!/bin/sh
# shellcheck shell=sh

set -eu

usage() {
	echo "Usage: ${0##*/} -c GENIMAGE_CONFIG_FILE -b BOARD_DIR [-d alpine] [-o OUTPUT_DIR]" >&2
}

export MINIME_SOURCE_ROOT="${MINIME_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

GENIMAGE_CFG=""
BOARD_DIR_OVERRIDE=""
DISTRO="alpine"
OUTPUT_DIR=""

opts="$(getopt -n "${0##*/}" -o b:c:d:o: -- "$@")" || exit $?
eval set -- "$opts"
while true; do
	case "$1" in
	-b)
		BOARD_DIR_OVERRIDE="$2"
		shift 2
		;;
	-c)
		GENIMAGE_CFG="$2"
		shift 2
		;;
	-d)
		DISTRO="$2"
		shift 2
		;;
	-o)
		OUTPUT_DIR="$2"
		shift 2
		;;
	--)
		shift
		break
		;;
	*)
		usage
		exit 1
		;;
	esac
done

if [ -z "$GENIMAGE_CFG" ]; then
	usage
	exit 1
fi

# ── Distro-specific resolution ───────────────────────────────────────────────
# All DISTRO-dependent logic lives here. The rest of the script must be
# distro-agnostic. See AGENTS.md for the canonical pattern.
case "${DISTRO}" in
alpine)
	DISTRO_SUFFIX="-alpine"
	;;
buildroot)
	DISTRO_SUFFIX=""
	# Buildroot wrapper passes bare board name; resolve to full external path.
	if [ -n "${BOARD_DIR_OVERRIDE}" ] && [ ! -d "${BOARD_DIR_OVERRIDE}" ]; then
		BOARD_DIR_OVERRIDE="${MINIME_SOURCE_ROOT}/../buildroot/external/board/${BOARD_DIR_OVERRIDE}"
	fi
	;;
*)
	echo "ERROR: -d must be 'alpine' or 'buildroot'" >&2
	exit 1
	;;
esac

if [ -n "${OUTPUT_DIR}" ]; then
	BINARIES_DIR="${OUTPUT_DIR}"
fi

if [ -n "${BOARD_DIR_OVERRIDE}" ]; then
	if [ -f "${BOARD_DIR_OVERRIDE}/board.env" ]; then
		BOARD_DIR="${BOARD_DIR_OVERRIDE}"
	elif [ -f "${MINIME_SOURCE_ROOT}/board/${BOARD_DIR_OVERRIDE}/board.env" ]; then
		BOARD_DIR="${MINIME_SOURCE_ROOT}/board/${BOARD_DIR_OVERRIDE}"
	else
		BOARD_DIR="${BOARD_DIR_OVERRIDE}"
	fi
else
	BOARD_DIR="$(dirname "$GENIMAGE_CFG")"
fi
SOC_NAME="$(basename "$BOARD_DIR")"

if [ ! -f "${BOARD_DIR}/board.env" ]; then
	echo "ERROR: ${BOARD_DIR}/board.env is missing!" >&2
	exit 1
fi

# shellcheck source=/dev/null
. "${BOARD_DIR}/board.env"

if [ -z "${DEFAULT_DTB:-}" ] || [ -z "${DTB_PATTERN:-}" ] || [ -z "${GENIMAGE_IMAGE_NAME:-}" ]; then
	echo "ERROR: board.env must define DEFAULT_DTB, DTB_PATTERN, and GENIMAGE_IMAGE_NAME!" >&2
	exit 1
fi

ROOTPATH_TMP="$(mktemp -d)"

cleanup() {
	rm -rf "${ROOTPATH_TMP}"
}
trap cleanup EXIT

# Export environment context for post-image.d stage scripts
export DISTRO DISTRO_SUFFIX BOARD_DIR SOC_NAME BINARIES_DIR BUILD_DIR HOST_DIR
export ROOTPATH_TMP GENIMAGE_CFG DEFAULT_DTB DTB_PATTERN AUTODETECT_SUPPORTED

# Execute modular post-image pipeline stages sequentially
STAGES_DIR="${MINIME_SOURCE_ROOT}/board/common/post-image.d"
for stage_script in "${STAGES_DIR}"/*.sh; do
	[ -x "${stage_script}" ] || continue
	echo "Running post-image stage: $(basename "${stage_script}")..."
	"${stage_script}"
done
