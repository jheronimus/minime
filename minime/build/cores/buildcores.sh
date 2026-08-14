#!/bin/sh
set -eu

# Shared libretro core builder for Minime.
#
# Builds every core listed in ./manifest (the single source of truth) for the
# active toolchain and produces a flat directory out/ of <name>_libretro.so
# files (plus any drastic shims) that MinUI and Allium both consume.
#
# Toolchain is taken from the environment:
#   CROSS_COMPILE  (make arg; the minime platform branches derive CC/CXX/AR
#                   from it, e.g. "ccache aarch64-linux-gnu-" or "" for native)
#   CC / CXX / AR  (used by cores whose Makefile does not branch on CROSS_COMPILE)
#   JOBS           (default: nproc)

CORES_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$CORES_DIR/manifest"
PATCHES_DIR="$CORES_DIR/patches"
SRC_DIR="$CORES_DIR/src"
OUT_DIR="$CORES_DIR/out"

CROSS_COMPILE="${CROSS_COMPILE:-}"
# Command-line make variables beat in-file assignments (file > env > CLI only
# for command-line), so CC/CXX/AR are passed to `make` as arguments. This is
# what lets cores like yabasanshiro (whose Makefile hard-sets `CC = gcc`) and
# drastic (`CC ?= gcc`) cross-compile, while patched cores derive the same
# values from CROSS_COMPILE.
CC="${CC:-${CROSS_COMPILE}gcc}"
CXX="${CXX:-${CROSS_COMPILE}g++}"
AR="${AR:-${CROSS_COMPILE}ar}"
JOBS="${JOBS:-$(nproc)}"

rm -rf "$OUT_DIR" "$SRC_DIR"
mkdir -p "$OUT_DIR" "$SRC_DIR"

export CROSS_COMPILE CC CXX AR

built=0
clone_retry() {
	# Retry clones a few times: unauthenticated git operations are prone to
	# GitHub rate-limits / transient network failures in CI.
	tries=3
	n=0
	while [ "$n" -lt "$tries" ]; do
		if "$@"; then
			return 0
		fi
		n=$((n + 1))
		echo "  clone attempt $n failed — retrying" >&2
		sleep 3
	done
	return 1
}

# shellcheck disable=SC2034  # autobump is consumed by the update-cores bot
while IFS='|' read -r core repo hash buildpath makefile flags patch platform core_so optional autobump; do
	[ -n "$core" ] || continue
	case "$core" in \#*) continue ;; esac

	echo "=== Building $core ==="

	src="$SRC_DIR/$core"
	if [ -n "$hash" ]; then
		# Pinned core: full clone (some pins are old commits not reachable shallowly).
		if ! clone_retry git clone --recursive "$repo" "$src" || ! (cd "$src" && git checkout "$hash"); then
			[ "$optional" = "1" ] && echo "WARNING: $core clone failed (optional) — skipping" >&2 && continue
			echo "ERROR: $core clone failed" >&2
			exit 1
		fi
	else
		if ! clone_retry git clone --depth 1 --recursive --shallow-submodules "$repo" "$src"; then
			[ "$optional" = "1" ] && echo "WARNING: $core clone failed (optional) — skipping" >&2 && continue
			echo "ERROR: $core clone failed" >&2
			exit 1
		fi
	fi

	# Apply the platform patch(es), in order (space-separated names in the
	# manifest `patch` field).
	if [ -n "$patch" ]; then
		for p in $patch; do
			if [ -f "$PATCHES_DIR/$p" ]; then
				if ! (cd "$src" && git apply -p1 "$PATCHES_DIR/$p"); then
					[ "$optional" = "1" ] && echo "WARNING: $core patch '$p' failed (optional) — skipping" >&2 && continue 2
					echo "ERROR: $core patch '$p' failed" >&2
					exit 1
				fi
			else
				echo "WARNING: patch '$p' for $core not found — skipping" >&2
			fi
		done
	fi

	# Build.
	bdir="$src${buildpath:+/$buildpath}"
	set -- make
	[ -n "$makefile" ] && set -- "$@" -f "$makefile"
	[ -n "$CROSS_COMPILE" ] && set -- "$@" CROSS_COMPILE="$CROSS_COMPILE"
	set -- "$@" CC="$CC" CXX="$CXX" AR="$AR" platform="${platform:-minime}"
	# shellcheck disable=SC2086
	if ! (cd "$bdir" && "$@" $flags -j"$JOBS"); then
		if [ "$optional" = "1" ]; then
			echo "WARNING: $core build failed (optional) — skipping" >&2
			continue
		fi
		echo "ERROR: $core build failed" >&2
		exit 1
	fi

	# Collect the .so (+ drastic shims, which must sit next to the core).
	so_name="${core_so:-${core}_libretro.so}"
	if [ ! -f "$bdir/$so_name" ]; then
		if [ "$optional" = "1" ]; then
			echo "WARNING: $core produced no $so_name (optional) — skipping" >&2
			continue
		fi
		echo "ERROR: expected $so_name in $bdir" >&2
		exit 1
	fi
	cp "$bdir/$so_name" "$OUT_DIR/$so_name"
	for shim in liblog.so libOpenSLES.so; do
		if [ -f "$bdir/$shim" ]; then
			cp "$bdir/$shim" "$OUT_DIR/$shim"
		fi
	done
	echo "$core|$so_name|$repo|${hash:-}" >> "$OUT_DIR/cores.txt"
	built=$((built + 1))
done < "$MANIFEST"

rm -rf "$SRC_DIR"
echo "Built $built core(s) into $OUT_DIR"
