#!/usr/bin/env python3
import os
import glob
import sys
import argparse
import subprocess

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Check Buildroot package and configuration rebuild status.")
parser.add_argument("--auto-clean", action="store_true", help="Automatically run necessary clean commands to fix out-of-date states.")
args = parser.parse_args()

# Paths
WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTERNAL = os.path.join(WORKSPACE, "external")

# Retrieve BR2_EXTERNAL buildroot-output directory, defaulting to Docker's volume or host path
BUILD_DIR = "/buildroot-output"
if not os.path.exists(BUILD_DIR):
    BUILD_DIR = os.path.expanduser("~/buildroot-output")
if not os.path.exists(BUILD_DIR):
    # Try looking in standard buildroot output folder in workspace
    alt_dir = os.path.join(WORKSPACE, "buildroot", "output")
    if os.path.exists(alt_dir):
        BUILD_DIR = alt_dir

if not os.path.exists(BUILD_DIR):
    print("Buildroot output directory not found. No build has been run yet.")
    sys.exit(0)

# Find all build outputs (e.g. board-specific or flat structure)
build_targets = []
if os.path.exists(os.path.join(BUILD_DIR, "build")):
    build_targets.append((BUILD_DIR, os.path.join(BUILD_DIR, "build")))

if os.path.isdir(BUILD_DIR):
    for item in os.listdir(BUILD_DIR):
        item_path = os.path.join(BUILD_DIR, item)
        if os.path.isdir(item_path):
            sb = os.path.join(item_path, "build")
            if os.path.exists(sb):
                build_targets.append((item_path, sb))

if not build_targets:
    print("No active build configurations or stamps found inside the output directory.")
    sys.exit(0)

packages_dir = os.path.join(EXTERNAL, "package")
if not os.path.exists(packages_dir):
    print("❌ Error: packages directory not found.")
    sys.exit(1)

has_warnings = False

# Loop over all active build directories
for target_dir, stamp_dir in build_targets:
    board_name = os.path.basename(target_dir) if target_dir != BUILD_DIR else "default"
    print(f"--- Scanning Build Output: {board_name} ({target_dir}) ---")
    
    # 1. Check Toolchain & Core (Full Rebuild Detector)
    toolchain_stamp = None
    stamps = glob.glob(os.path.join(stamp_dir, "toolchain-*", ".stamp_installed"))
    if stamps:
        toolchain_stamp = os.path.getmtime(stamps[0])

    dot_config = os.path.join(target_dir, ".config")
    if toolchain_stamp and os.path.exists(dot_config):
        config_mtime = os.path.getmtime(dot_config)
        if config_mtime > toolchain_stamp:
            print("⚠️  WARNING: Core system configuration (.config) changed after toolchain build!")
            if args.auto-clean:
                print(f"🧹 Auto-cleaning: Running 'make clean BOARD={board_name}'...")
                subprocess.run(["make", "clean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                print("✨ Clean complete. Re-run the build to start fresh.")
                sys.exit(0)
            else:
                print("👉 RECOMMENDED ACTION: A full rebuild is recommended ('make clean && make image')\n")
                has_warnings = True

    # 2. Check Package rules & Patches
    for pkg in os.listdir(packages_dir):
        pkg_dir = os.path.join(packages_dir, pkg)
        if not os.path.isdir(pkg_dir):
            continue

        pkg_stamps = glob.glob(os.path.join(stamp_dir, f"{pkg}-*"))
        if not pkg_stamps:
            continue

        build_path = pkg_stamps[0]
        stamp_configured = os.path.join(build_path, ".stamp_configured")
        stamp_patched = os.path.join(build_path, ".stamp_patched")

        if not os.path.exists(stamp_configured):
            continue

        # A. Check if package rules (*.mk, Config.in) are newer than stamp_configured
        rules_files = [os.path.join(pkg_dir, f) for f in os.listdir(pkg_dir) if os.path.isfile(os.path.join(pkg_dir, f))]
        if rules_files:
            rules_newest = max(os.path.getmtime(f) for f in rules_files)
            if rules_newest > os.path.getmtime(stamp_configured):
                print(f"❌ PACKAGE OUT-OF-DATE: '{pkg}' build rules or configuration changed.")
                if args.auto-clean:
                    print(f"   🧹 Auto-cleaning: Running 'make {pkg}-dirclean BOARD={board_name}'...")
                    subprocess.run(["make", f"{pkg}-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                else:
                    print(f"   👉 ACTION REQUIRED: Run 'make {pkg}-rebuild'\n")
                    has_warnings = True

        # B. Check if board-specific patches are newer than stamp_patched
        patch_patterns = [
            os.path.join(EXTERNAL, "board", "*", "patches", pkg, "*.patch"),
            os.path.join(EXTERNAL, "board", "common", "patches", pkg, "*.patch"),
        ]
        for pattern in patch_patterns:
            patches = glob.glob(pattern)
            if not patches:
                continue
            newest_patch = max(os.path.getmtime(p) for p in patches)
            if os.path.exists(stamp_patched) and newest_patch > os.path.getmtime(stamp_patched):
                print(f"❌ PATCHES OUT-OF-DATE: '{pkg}' has newer patches that have not been applied.")
                if args.auto-clean:
                    print(f"   🧹 Auto-cleaning: Running 'make {pkg}-dirclean BOARD={board_name}'...")
                    subprocess.run(["make", f"{pkg}-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                else:
                    print(f"   👉 ACTION REQUIRED: Run 'make {pkg}-dirclean && make {pkg}'\n")
                    has_warnings = True

if not has_warnings:
    print("✅ All compiled packages are fully up-to-date with your local source files!")
