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

def check_mesa_panfrost_version(workspace):
    mesa_mk = os.path.join(workspace, "buildroot", "package", "mesa3d", "mesa3d.mk")
    panfrost_mk = os.path.join(workspace, "external", "package", "panfrost", "panfrost.mk")

    if not os.path.exists(mesa_mk):
        return False

    if not os.path.exists(panfrost_mk):
        return False

    mesa_ver = None
    with open(mesa_mk, "r") as f:
        for line in f:
            if line.startswith("MESA3D_VERSION ="):
                mesa_ver = line.split("=")[1].strip()
                break

    panfrost_ver = None
    with open(panfrost_mk, "r") as f:
        for line in f:
            if line.startswith("PANFROST_VERSION ="):
                panfrost_ver = line.split("=")[1].strip()
                break

    if not mesa_ver or not panfrost_ver:
        return False

    panfrost_base = panfrost_ver.split('r')[0]
    if mesa_ver != panfrost_base:
        print("=" * 80)
        print(f"⚠️  WARNING: Mesa3D/Panfrost Version Mismatch Detected!")
        print(f"   - Upstream Buildroot Mesa3D: {mesa_ver}")
        print(f"   - Custom Panfrost Prebuilt base: {panfrost_base} (Full: {panfrost_ver})")
        print("   This version mismatch can cause ABI/runtime crashes or loading failures.")
        print("   👉 RECOMMENDED ACTION:")
        print(f"      1. Update PANFROST_VERSION in external/package/panfrost/panfrost.mk to match {mesa_ver} (e.g., {mesa_ver}r1)")
        print(f"      2. Run 'make panfrost BOARD=h700' locally, or trigger the GitHub Action")
        print(f"         'Build and Release Panfrost Prebuilt' to generate new prebuilt assets.")
        print("=" * 80)
        print()
        return True
    return False

# Paths
WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTERNAL = os.path.join(WORKSPACE, "external")

# Check version consistency between upstream Mesa3D and our custom panfrost package
has_warnings = check_mesa_panfrost_version(WORKSPACE)

# Retrieve BR2_EXTERNAL buildroot-output directory, defaulting to Podman/container's output directory or host path
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

# has_warnings is initialized above with the Mesa/Panfrost version check

# Loop over all active build directories
for target_dir, stamp_dir in build_targets:
    board_name = os.path.basename(target_dir) if target_dir != BUILD_DIR else "default"
    print(f"--- Scanning Build Output: {board_name} ({target_dir}) ---")
    
    # 1. Check Toolchain & Core (Full Rebuild Detector)
    toolchain_stamp = None
    stamps = glob.glob(os.path.join(stamp_dir, "toolchain-*", ".stamp_installed"))
    if stamps:
        toolchain_stamp = os.path.getmtime(stamps[0])

    if toolchain_stamp:
        # Core configuration source files that actually define the build
        config_files = [
            os.path.join(WORKSPACE, "external", "configs", f"minime_{board_name}_defconfig"),
            os.path.join(WORKSPACE, "external", "board", "common", "busybox.config"),
            os.path.join(WORKSPACE, "external", "board", "common", "tiny-base.config"),
        ]
        board_dir = os.path.join(WORKSPACE, "external", "board", board_name)
        if os.path.exists(board_dir):
            for root, _, files in os.walk(board_dir):
                for f in files:
                    if f.endswith(".config") or f == "board.env":
                        config_files.append(os.path.join(root, f))

        newest_config_time = 0
        for f in config_files:
            if os.path.exists(f):
                newest_config_time = max(newest_config_time, os.path.getmtime(f))

        if newest_config_time > toolchain_stamp:
            print(f"⚠️  WARNING: Core system configuration files changed after toolchain build for board {board_name}!")
            if args.auto_clean:
                print(f"🧹 Auto-cleaning: Running 'make clean BOARD={board_name}'...")
                subprocess.run(["make", "clean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                print("✨ Clean complete. Re-run the build to start fresh.")
                sys.exit(0)
            else:
                print("👉 RECOMMENDED ACTION: A full rebuild is recommended ('make clean && make image')\n")
                has_warnings = True

    # 1b. Check for incomplete/failed package builds (Self-Healing)
    if os.path.exists(stamp_dir):
        for item in os.listdir(stamp_dir):
            item_path = os.path.join(stamp_dir, item)
            if not os.path.isdir(item_path) or item.startswith('.') or item.startswith('buildroot'):
                continue
            stamp_built = os.path.join(item_path, ".stamp_built")
            if not os.path.exists(stamp_built):
                parts = item.split('-')
                pkg_name = "-".join(parts[:-1]) if len(parts) > 1 else item
                print(f"⚠️  WARNING: Package '{pkg_name}' ({item}) build was interrupted or failed in the previous run.")
                if args.auto_clean:
                    print(f"   🧹 Auto-cleaning: Running 'make {pkg_name}-dirclean BOARD={board_name}'...")
                    subprocess.run(["make", f"{pkg_name}-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                else:
                    print(f"   👉 RECOMMENDED ACTION: Run 'make {pkg_name}-dirclean BOARD={board_name}' to reset it.\n")
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
                if args.auto_clean:
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
                if args.auto_clean:
                    print(f"   🧹 Auto-cleaning: Running 'make {pkg}-dirclean BOARD={board_name}'...")
                    subprocess.run(["make", f"{pkg}-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                else:
                    print(f"   👉 ACTION REQUIRED: Run 'make {pkg}-dirclean && make {pkg}'\n")
                    has_warnings = True

if not has_warnings:
    print("✅ All compiled packages are fully up-to-date with your local source files!")
