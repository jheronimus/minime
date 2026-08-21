#!/bin/sh
set -eu

# Shared libretro core builder for Minime.
#
# Builds emulator cores from packages/cores/*/core.ini for the active
# toolchain and produces a flat directory out/ of <name>_libretro.so
# files consumed by MinUI, Allium, and muOS.
#
# Usage:
#   ./build.sh [core_name]

CORES_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$CORES_DIR/src"
OUT_DIR="$CORES_DIR/out"

TARGET_CORE="${1:-}"
FORCE="${FORCE:-0}"

CROSS_COMPILE="${CROSS_COMPILE:-}"
CC="${CC:-${CROSS_COMPILE}gcc}"
CXX="${CXX:-${CROSS_COMPILE}g++}"
AR="${AR:-${CROSS_COMPILE}ar}"
JOBS="${JOBS:-$(nproc)}"
PARALLEL_CORES="${PARALLEL_CORES:-}"

if [ -z "$PARALLEL_CORES" ]; then
	if [ -n "$TARGET_CORE" ]; then
		PARALLEL_CORES=1
	elif [ "$JOBS" -ge 4 ]; then
		PARALLEL_CORES=2
	else
		PARALLEL_CORES=1
	fi
fi

CORE_JOBS=$(( (JOBS + PARALLEL_CORES - 1) / PARALLEL_CORES ))
[ "$CORE_JOBS" -lt 1 ] && CORE_JOBS=1

mkdir -p "$OUT_DIR" "$SRC_DIR"

export CROSS_COMPILE CC CXX AR

clone_retry() {
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

get_ini_val() {
	file="$1"
	key="$2"
	grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

build_core() {
	dir="$1"
	core="$(basename "$dir")"
	ini="$dir/core.ini"
	[ -f "$ini" ] || return 0

	repo="$(get_ini_val "$ini" "repo")"
	hash="$(get_ini_val "$ini" "hash")"
	buildpath="$(get_ini_val "$ini" "buildpath")"
	makefile="$(get_ini_val "$ini" "makefile")"
	flags="$(get_ini_val "$ini" "flags")"
	platform="$(get_ini_val "$ini" "platform")"
	[ -z "$platform" ] && platform="minime"
	core_so="$(get_ini_val "$ini" "core_so")"
	optional="$(get_ini_val "$ini" "optional")"
	[ -z "$optional" ] && optional="0"
	builder="$(get_ini_val "$ini" "builder")"
	[ -z "$builder" ] && builder="make"

	so_name="${core_so:-${core}_libretro.so}"

	if [ "$FORCE" != "1" ] && [ -s "$OUT_DIR/$so_name" ]; then
		echo "=== Skipping $core ($so_name already built) ==="
		echo "$core|$so_name|$repo|${hash:-}" >"$OUT_DIR/.core_${core}"
		return 0
	fi

	echo "=== Building $core ==="

	src="$SRC_DIR/$core"
	rm -rf "$src"

	if [ -n "$hash" ]; then
		if ! clone_retry git clone --filter=blob:none --no-checkout "$repo" "$src" || \
		   ! (cd "$src" && git checkout -q "$hash") || \
		   ! (cd "$src" && git submodule update --init --recursive --depth 1 --recommend-shallow 2>/dev/null || true); then
			if [ "$optional" = "1" ]; then
				echo "WARNING: $core clone failed (optional) — skipping" >&2
				return 0
			fi
			echo "ERROR: $core clone failed" >&2
			return 1
		fi
	else
		if ! clone_retry git clone --depth 1 --recursive --shallow-submodules "$repo" "$src"; then
			if [ "$optional" = "1" ]; then
				echo "WARNING: $core clone failed (optional) — skipping" >&2
				return 0
			fi
			echo "ERROR: $core clone failed" >&2
			return 1
		fi
	fi

	for p in "$dir"/*.patch; do
		[ -f "$p" ] || continue
		echo "  Applying patch $(basename "$p")..."
		if ! (cd "$src" && git apply -p1 "$p"); then
			if [ "$optional" = "1" ]; then
				echo "WARNING: $core patch '$(basename "$p")' failed (optional) — skipping" >&2
				return 0
			fi
			echo "ERROR: $core patch '$(basename "$p")' failed" >&2
			return 1
		fi
	done

	bdir="$src${buildpath:+/$buildpath}"
	if [ "$builder" = "cmake" ]; then
		# shellcheck disable=SC2086
		if ! (cd "$bdir" && cmake -B build -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_AR="$AR" $flags &&
			make -C build -j"$CORE_JOBS"); then
			if [ "$optional" = "1" ]; then
				echo "WARNING: $core build failed (optional) — skipping" >&2
				return 0
			fi
			echo "ERROR: $core build failed" >&2
			return 1
		fi
	else
		set -- make
		[ -n "$makefile" ] && set -- "$@" -f "$makefile"
		[ -n "$CROSS_COMPILE" ] && set -- "$@" CROSS_COMPILE="$CROSS_COMPILE"
		set -- "$@" CC="$CC" CXX="$CXX" AR="$AR" platform="$platform"
		# shellcheck disable=SC2086
		if ! (cd "$bdir" && "$@" $flags -j"$CORE_JOBS"); then
			if [ "$optional" = "1" ]; then
				echo "WARNING: $core build failed (optional) — skipping" >&2
				return 0
			fi
			echo "ERROR: $core build failed" >&2
			return 1
		fi
	fi

	so_path="$bdir/$so_name"
	if [ ! -f "$so_path" ] && [ "$builder" = "cmake" ]; then
		so_path="$(find "$bdir/build" -name "$so_name" -print -quit 2>/dev/null || true)"
	fi
	if [ -z "$so_path" ] || [ ! -f "$so_path" ]; then
		if [ "$optional" = "1" ]; then
			echo "WARNING: $core produced no $so_name (optional) — skipping" >&2
			return 0
		fi
		echo "ERROR: expected $so_name in $bdir" >&2
		return 1
	fi
	cp "$so_path" "$OUT_DIR/$so_name"
	for shim in liblog.so libOpenSLES.so libashmem.so libandroid.so; do
		if [ -f "$bdir/$shim" ]; then
			cp "$bdir/$shim" "$OUT_DIR/$shim"
		fi
	done

	echo "$core|$so_name|$repo|${hash:-}" >"$OUT_DIR/.core_${core}"
	rm -rf "$src"
	return 0
}

status_dir=$(mktemp -d)
running=0

for dir in "$CORES_DIR"/*/; do
	[ -d "$dir" ] || continue
	core="$(basename "$dir")"
	[ "$core" = "src" ] && continue
	[ "$core" = "out" ] && continue

	if [ -n "$TARGET_CORE" ] && [ "$core" != "$TARGET_CORE" ]; then
		continue
	fi

	ini="$dir/core.ini"
	[ -f "$ini" ] || continue

	if [ "$PARALLEL_CORES" -le 1 ]; then
		if ! build_core "$dir"; then
			touch "$status_dir/fail_$core"
		fi
	else
		(
			if ! build_core "$dir"; then
				touch "$status_dir/fail_$core"
			fi
		) &
		running=$((running + 1))
		if [ "$running" -ge "$PARALLEL_CORES" ]; then
			wait
			running=0
		fi
	fi
done

wait

fail_count=$(find "$status_dir" -name "fail_*" 2>/dev/null | wc -l)
rm -rf "$status_dir"

if [ "$fail_count" -gt 0 ]; then
	echo "ERROR: $fail_count core build(s) failed" >&2
	exit 1
fi

: >"$OUT_DIR/cores.txt"
for cf in "$OUT_DIR"/.core_*; do
	[ -f "$cf" ] || continue
	cat "$cf" >>"$OUT_DIR/cores.txt"
	rm -f "$cf"
done

rm -rf "$SRC_DIR"
built=$(find "$OUT_DIR" -maxdepth 1 -name "*_libretro.so" 2>/dev/null | wc -l)
echo "Built $built core(s) into $OUT_DIR"
