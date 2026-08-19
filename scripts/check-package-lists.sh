#!/bin/sh
# check-package-lists.sh: cross-check that every local Minime package that is
# referenced is also built and installed on both targets. A package listed in
# world-common (Alpine) or common.config (Buildroot) but not wired into the
# build fails at rootfs assembly — catch it statically.
# UI-bundled tools (dufs, syncthing, bezels) are packaged separately and are
# not part of the rootfs package list. Max SLOC: 100

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

# ── Alpine ────────────────────────────────────────────────────────────────────
build_pkgs="$(sed -n 's/^[[:space:]]*ALPINE_PKGS="\(.*\)"$/\1/p' \
	"${ROOT}/packages/components/alpine/scripts/build.sh")"
[ -n "$build_pkgs" ] || {
	echo "ERROR: cannot parse ALPINE_PKGS from build.sh" >&2
	exit 1
}

for p in $build_pkgs; do
	[ -d "${ROOT}/packages/components/alpine/aports/${p}" ] ||
		{
			echo "ERROR: build.sh builds ${p} but aports/${p} missing" >&2
			errors=$((errors + 1))
		}
	grep -qw "${p}" "${ROOT}/packages/components/alpine/configs/world-common" ||
		{
			echo "ERROR: ${p} is built but missing from world-common" >&2
			errors=$((errors + 1))
		}
done

for d in "${ROOT}"/packages/components/alpine/aports/*; do
	[ -d "$d" ] || continue
	name="${d##*/}"
	[ "$name" = "tinykernel" ] && continue
	grep -qw "$name" "${ROOT}/packages/components/alpine/configs/world-common" || continue
	echo "$build_pkgs" | grep -qw "$name" ||
		{
			echo "ERROR: world-common ${name} is missing from build.sh ALPINE_PKGS" >&2
			errors=$((errors + 1))
		}
done

# ── Buildroot (Minime external packages only) ─────────────────────────────────
for sym in $(grep -oE '^BR2_PACKAGE_[A-Z0-9_]+=y' \
	"${ROOT}/packages/components/buildroot/external/configs/common.config" | sed 's/=y$//'); do
	name="${sym#BR2_PACKAGE_}"
	dir="$(echo "$name" | tr '[:upper:]_' '[:lower:]-')"
	[ -d "${ROOT}/packages/components/buildroot/external/package/${dir}" ] || continue
	grep -qs "package/${dir}/Config.in" "${ROOT}/packages/components/buildroot/external/Config.in" ||
		{
			echo "ERROR: ${sym} enabled but package/${dir}/Config.in not sourced in external/Config.in" >&2
			errors=$((errors + 1))
		}
done

[ "$errors" -eq 0 ] || exit 1
echo "package list check passed"
