#!/usr/bin/env sh
set -eu

MODE="check"
STRICT_COMPLEXITY=0
CCN_THRESHOLD=10

for arg in "$@"; do
	case "$arg" in
		-i|--format|--apply)
			MODE="format"
			;;
		--check)
			MODE="check"
			;;
		--complexity|--check-complexity)
			MODE="complexity"
			;;
		--strict-complexity)
			STRICT_COMPLEXITY=1
			;;
		*)
			echo "Usage: $0 [--check | -i | --format | --complexity] [--strict-complexity]" >&2
			exit 1
			;;
	esac
done

echo "Checking MinUI C code formatting and conventions..."
if [ ! -d "packages/ui/minui/workspace/minime" ]; then
	echo "ERROR: packages/ui/minui/workspace/minime directory not found" >&2
	exit 1
fi

CFG="packages/ui/minui/.clang-format"
if [ ! -f "$CFG" ]; then
	echo "ERROR: $CFG configuration not found" >&2
	exit 1
fi

FILES=$(find packages/ui/minui/workspace/minime -not -path "*/cores/src/*" -type f \( -name "*.c" -o -name "*.h" \) | sort)

if [ "$MODE" = "format" ]; then
	echo "Formatting MinUI C files in-place with clang-format..."
	echo "$FILES" | xargs mise exec -- clang-format -i
	echo "MinUI C files reformatted."
	exit 0
fi

if [ "$MODE" = "complexity" ]; then
	echo "Auditing MinUI C cyclomatic complexity (CCN > $CCN_THRESHOLD)..."
	# shellcheck disable=SC2086
	if mise exec -- lizard $FILES -C "$CCN_THRESHOLD" -w; then
		echo "All MinUI C functions within CCN <= $CCN_THRESHOLD."
		exit 0
	else
		echo "Cyclomatic complexity audit complete."
		if [ "$STRICT_COMPLEXITY" -eq 1 ]; then
			exit 1
		fi
		exit 0
	fi
fi

# Dry-run format check
echo "$FILES" | xargs mise exec -- clang-format --dry-run --Werror

# Static convention and anti-pattern checks
FAILURES=0

for f in $FILES; do
	# Check for Doxygen docblock style (@param, @return, @brief, /**)
	if grep -nE '(\/\*\*|@param|@return|@brief)' "$f" >/dev/null 2>&1; then
		echo "ERROR: $f contains Doxygen docblock style; use single-line // comments instead:" >&2
		grep -nE '(\/\*\*|@param|@return|@brief)' "$f" >&2 || true
		FAILURES=$((FAILURES + 1))
	fi

	# Check header include order: defines.h must precede api.h
	if grep -q '"api.h"' "$f" && grep -q '"defines.h"' "$f"; then
		api_line=$(grep -n '"api.h"' "$f" | head -n 1 | cut -d: -f1)
		defines_line=$(grep -n '"defines.h"' "$f" | head -n 1 | cut -d: -f1)
		if [ "$api_line" -lt "$defines_line" ]; then
			echo "ERROR: $f includes api.h before defines.h (line $api_line vs $defines_line)" >&2
			FAILURES=$((FAILURES + 1))
		fi
	fi
done

if [ "$FAILURES" -gt 0 ]; then
	echo "MinUI C convention validation failed with $FAILURES error(s)." >&2
	exit 1
fi

echo "Auditing cyclomatic complexity (CCN > $CCN_THRESHOLD)..."
# shellcheck disable=SC2086
if ! mise exec -- lizard $FILES -C "$CCN_THRESHOLD" -w; then
	echo "WARNING: Functions above CCN $CCN_THRESHOLD flagged for review/refactoring."
	if [ "$STRICT_COMPLEXITY" -eq 1 ]; then
		echo "ERROR: Strict complexity enforcement failed." >&2
		exit 1
	fi
fi

echo "MinUI C validation passed cleanly."
