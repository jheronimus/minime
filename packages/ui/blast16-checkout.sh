#!/bin/sh
# Checkout the private Blast16 frontend at the pinned gitlink ref into
# packages/ui/blast16. The submodule is declared with `update = none` in
# .gitmodules, so recursive checkouts skip it; this helper is used by the
# blast16 build job.
#
# The repo is private, so authentication uses the BLAST16_PAT secret through a
# per-repo URL rewrite scoped to github.com/jheronimus/blast16 only (the runner
# still fetches every other submodule with the default checkout credentials).
#
# Usage: blast16-checkout.sh <ref>
#   <ref>  commit SHA (from the parent gitlink) or a branch/tag name
#
# Env:  BLAST16_PAT   fine-grained PAT with read-only Contents access to the
#                     jheronimus/blast16 repo (Actions secret stored as BLAST)

set -eu

REF="${1:?usage: blast16-checkout.sh <ref>}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PATH_UI="$ROOT_DIR/packages/ui/blast16"

# Already present = a real checkout exists. Git may leave an EMPTY directory at
# the path for a skipped (update=none) submodule, so a plain -d test is not
# enough.
if [ -e "$PATH_UI/.git" ] || [ -d "$PATH_UI/src" ]; then
	echo "blast16 already present at $PATH_UI" >&2
	exit 0
fi

if [ -n "${BLAST16_PAT:-}" ]; then
	git config --global url."https://x-access-token:${BLAST16_PAT}@github.com/jheronimus/blast16".insteadOf "https://github.com/jheronimus/blast16"
fi

git clone --depth 1 https://github.com/jheronimus/blast16.git "$PATH_UI"
git -C "$PATH_UI" fetch --depth 1 origin "$REF"
git -C "$PATH_UI" checkout "$REF"
git submodule absorbgitdirs packages/ui/blast16 2>/dev/null || true

echo "blast16 checkout ready at $PATH_UI ($REF)"
