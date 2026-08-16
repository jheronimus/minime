#!/bin/sh
# Install git hooks that run `just validate-static` before every commit/push.
# The pre-push hook also forwards to `git lfs pre-push` so LFS-tracked roms
# still upload — it replaces the LFS pre-push hook, it does not clobber it.
# Run once per clone (after `mise install`).

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

write_hook() {
	name="$1"
	body="$2"
	printf '%s\n' "$body" >"$REPO_ROOT/.git/hooks/$name"
	chmod +x "$REPO_ROOT/.git/hooks/$name"
}

write_hook pre-commit '#!/bin/sh
set -eu
echo "==> pre-commit: running just validate-static"
exec just validate-static'

write_hook pre-push '#!/bin/sh
set -eu
echo "==> pre-push: running just validate-static"
just validate-static
if command -v git-lfs >/dev/null 2>&1; then
    exec git lfs pre-push "$@"
fi'

echo "Installed pre-commit / pre-push hooks (validate-static; pre-push also forwards to git-lfs)."
