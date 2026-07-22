#!/usr/bin/env python3
import sys
import os
from pathlib import Path

# Directories to scan for patches
PATCH_SEARCH_DIRS = [
    "alpine/board",
    "alpine/aports",
    "buildroot/external/board",
    "buildroot/external/package",
]

# Files/extensions that can reference patches
MANIFEST_FILES = ["APKBUILD", "Makefile", "series"]
MANIFEST_EXTENSIONS = [".mk", ".sh", ".py", ".yml", ".config"]

def main():
    root_dir = Path(".")
    patch_files = []

    for d in PATCH_SEARCH_DIRS:
        p_dir = root_dir / d
        if p_dir.exists():
            for p in p_dir.rglob("*.patch"):
                patch_files.append(p)

    if not patch_files:
        print("No patch files found to check.")
        sys.exit(0)

    print(f"Checking {len(patch_files)} patch file(s) for references in build manifests...")

    # Build reference text cache across all manifest files in the repo
    reference_contents = []
    for search_dir in ["alpine", "buildroot", "scripts", ".github"]:
        s_path = root_dir / search_dir
        if not s_path.exists():
            continue
        for fpath in s_path.rglob("*"):
            if fpath.is_file() and (fpath.name in MANIFEST_FILES or fpath.suffix in MANIFEST_EXTENSIONS):
                try:
                    text = fpath.read_text(encoding="utf-8", errors="ignore")
                    reference_contents.append((str(fpath), text))
                except Exception:
                    pass

    orphaned = []
    for patch in patch_files:
        patch_name = patch.name
        rel_path = str(patch.relative_to(root_dir))
        
        # Check if patch filename is mentioned in any manifest
        found = False
        for m_file, m_text in reference_contents:
            if patch_name in m_text or rel_path in m_text:
                found = True
                break
        
        if not found:
            # Special case: uboot/kernel patch directories where patches are applied automatically via *.patch wildcard
            parent_dir_name = patch.parent.name
            if parent_dir_name in ("patches", "linux", "uboot", "atf", "sdl2"):
                # Check if parent folder or *.patch wildcard is referenced in nearby Makefile/APKBUILD
                for m_file, m_text in reference_contents:
                    if str(patch.parent) in m_text or (parent_dir_name in m_file and "*.patch" in m_text):
                        found = True
                        break

        if not found:
            orphaned.append(rel_path)

    if orphaned:
        print(f"\n[ERROR] Found {len(orphaned)} unreferenced/orphaned patch file(s):")
        for o in orphaned:
            print(f"  - {o}")
        sys.exit(1)
    else:
        print("Patch validation passed cleanly. All patches are properly referenced.")
        sys.exit(0)

if __name__ == "__main__":
    main()
