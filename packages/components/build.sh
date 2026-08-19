#!/bin/sh
set -eu

# Minime Components Builder
#
# Usage:
#   ./build.sh <alpine|buildroot> <board>

TARGET="${1:-}"
BOARD="${2:-rk3566}"

if [ -z "$TARGET" ]; then
	echo "Usage: $0 <alpine|buildroot> [board]" >&2
	exit 1
fi

COMPONENTS_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$TARGET" in
alpine)
	make -C "${COMPONENTS_DIR}/alpine" components BOARD="${BOARD}"
	;;
buildroot)
	make -C "${COMPONENTS_DIR}/buildroot" components BOARD="${BOARD}"
	;;
*)
	echo "Unknown target: $TARGET (expected alpine or buildroot)" >&2
	exit 1
	;;
esac
