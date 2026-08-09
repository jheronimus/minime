#!/usr/bin/env sh
set -eu

echo "Checking YabaSanshiro libretro glue formatting (clang-format)..."
if [ ! -d "src/yabause/yabause/src/libretro" ]; then
	echo "ERROR: src/yabause/yabause/src/libretro directory not found" >&2
	exit 1
fi

# Only our authored glue files. libretro-common/ is vendored upstream code
# and must not be reformatted.
find src/yabause/yabause/src/libretro -maxdepth 1 -type f \( -name "*.c" -o -name "*.h" \) |
	sort | xargs mise exec -- clang-format --dry-run --Werror

echo "YabaSanshiro libretro glue validation passed cleanly."
