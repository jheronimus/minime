#!/usr/bin/env python3
"""Verify that all binaries referenced by Minime OpenRC init scripts exist in the rootfs.

Usage: check-openrc-paths.py <rootfs_dir> [<overlay_src_dir> ...]

Only checks scripts whose names exist in one of the overlay source directories
so that Alpine's own built-in services (bootmisc, cgroups, devfs, etc.) are
not validated — they may reference binaries not present in a minimal rootfs.

Checks command=, start-stop-daemon -x, and start-stop-daemon --exec paths.
Exits 0 if all paths resolve, 1 if any are missing.
"""

import sys
import os
import re
from pathlib import Path


# usr-merge: on Alpine 3.24+ with usr-merge, /bin -> /usr/bin and /sbin -> /usr/sbin.
# busybox --install -s creates symlinks in its own directory (/usr/bin/), so
# applets like tcpsvd live at /usr/bin/tcpsvd, not /usr/sbin/tcpsvd.
# When a path doesn't exist, try the usr-merge equivalent directories.
_SBIN_TO_BIN = {
    "/usr/sbin": ["/usr/bin", "/sbin", "/bin"],
    "/sbin": ["/usr/sbin", "/usr/bin", "/bin"],
}


def _check_path(rootfs: Path, path: str) -> bool:
    """Check if path exists in rootfs, trying usr-merge fallbacks."""
    p = rootfs / path.lstrip("/")
    if p.exists():
        return True

    # Try usr-merge fallback directories
    prefix = "/" + path.strip("/").split("/")[0]
    suffix = "/".join(path.strip("/").split("/")[1:])
    for fb in _SBIN_TO_BIN.get(prefix, []):
        if (rootfs / f"{fb.strip('/')}/{suffix}").exists():
            return True

    return False


def extract_paths(script: Path) -> list[tuple[int, str]]:
    """Extract binary paths from an OpenRC init script."""
    paths: list[tuple[int, str]] = []
    try:
        lines = script.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return paths

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue

        # command="/usr/sbin/foo"
        m = re.match(r'^command="([^"]+)"', stripped)
        if m:
            paths.append((lineno, m.group(1).split()[0]))
            continue

        # start-stop-daemon ... -x /usr/sbin/foo
        # --exec /usr/sbin/foo
        for m in re.finditer(r"-(?:x|exec)\s+(\S+)", stripped):
            val = m.group(1)
            if not val.startswith("-") and "/" in val:
                paths.append((lineno, val))

    return paths


def collect_owned_names(overlay_dirs: list[Path]) -> set[str]:
    """Collect init script names that exist in any overlay directory."""
    names: set[str] = set()
    for overlay_dir in overlay_dirs:
        initd = overlay_dir / "etc" / "init.d"
        if initd.is_dir():
            for f in initd.iterdir():
                if f.is_file() and not f.name.startswith("."):
                    names.add(f.name)
    return names


def main() -> int:
    if len(sys.argv) < 2:
        print(
            f"Usage: {sys.argv[0]} <rootfs_dir> [<overlay_src_dir> ...]",
            file=sys.stderr,
        )
        return 2

    rootfs = Path(sys.argv[1])
    if not rootfs.is_dir():
        print(f"ERROR: {rootfs} is not a directory", file=sys.stderr)
        return 2

    initd = rootfs / "etc" / "init.d"
    if not initd.is_dir():
        print(f"ERROR: {initd} does not exist", file=sys.stderr)
        return 2

    # Collect all init script names from rootfs
    all_scripts = sorted(
        f for f in initd.iterdir() if f.is_file() and not f.name.startswith(".")
    )

    # Determine which scripts are owned by the overlay (user-provided dirs)
    owned = set()
    if len(sys.argv) > 2:
        overlay_dirs = [Path(arg) for arg in sys.argv[2:]]
        owned = collect_owned_names(overlay_dirs)
        scripts = [s for s in all_scripts if s.name in owned]
        print(
            f"Checking {len(scripts)} Minime-owned init script(s) "
            f"(of {len(all_scripts)} total) for missing binaries..."
        )
    else:
        scripts = all_scripts
        print(
            f"Checking all {len(scripts)} OpenRC init script(s) for missing binaries..."
        )

    errors = 0
    for script in scripts:
        for lineno, path in extract_paths(script):
            if not _check_path(rootfs, path):
                print(f"  [ERROR] {script.name}:{lineno}: {path} — not found in rootfs")
                errors += 1

    if errors > 0:
        print(f"\nOpenRC path validation failed with {errors} missing binary(ies).")
        return 1
    else:
        print("OpenRC path validation passed cleanly. All referenced binaries exist.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
