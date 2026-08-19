#!/usr/bin/env sh
set -eu

echo "Checking MinUI C code formatting (clang-format)..."
if [ ! -d "packages/ui/minui/workspace/minime" ]; then
    echo "ERROR: packages/ui/minui/workspace/minime directory not found" >&2
    exit 1
fi

find packages/ui/minui/workspace/minime -not -path "*/cores/src/*" -type f \( -name "*.c" -o -name "*.h" \) \
    | sort | xargs mise exec -- clang-format --dry-run --Werror

echo "MinUI C validation passed cleanly."
