#!/bin/sh
# Sparse-checkout the muOS internal payload (share/ + script/) into
# minime/ui/muos/internal without pulling the whole ~1 GB tree (bin/, init/,
# device/, ...). The submodule is declared with `update = none` in .gitmodules,
# so recursive checkouts skip it; this helper is used by the muos build jobs
# and by update-submodules.yml.
#
# Usage: muos-checkout-internal.sh <ref>
#   <ref>  commit SHA (from the parent gitlink) or a branch/tag name

set -eu

REF="${1:?usage: muos-checkout-internal.sh <ref>}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PATH_INTERNAL="$ROOT_DIR/minime/ui/muos/internal"

if [ -d "$PATH_INTERNAL" ]; then
	echo "muos internal already present at $PATH_INTERNAL" >&2
	exit 0
fi

git clone --filter=blob:none --sparse --depth 1 \
	https://github.com/MustardOS/internal.git "$PATH_INTERNAL"
git -C "$PATH_INTERNAL" sparse-checkout set share script
git -C "$PATH_INTERNAL" fetch --depth 1 origin "$REF"
git -C "$PATH_INTERNAL" checkout "$REF"
git submodule absorbgitdirs minime/ui/muos/internal 2>/dev/null || true

echo "muos internal checkout ready at $PATH_INTERNAL ($REF)"
