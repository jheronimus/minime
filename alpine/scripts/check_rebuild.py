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

def get_file_mtime(path):
    """Returns Git commit timestamp if clean, otherwise filesystem mtime."""
    if not os.path.exists(path):
        return 0
    try:
        # Check if the file is locally modified
        status = subprocess.run(
            ["git", "status", "--porcelain", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            cwd=os.path.dirname(os.path.abspath(path))
        )
        if status.returncode == 0 and status.stdout.strip():
            return os.path.getmtime(path)

        # File is clean, get commit timestamp
        log = subprocess.run(
            ["git", "log", "-1", "--format=%ct", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            cwd=os.path.dirname(os.path.abspath(path))
        )
        if log.returncode == 0 and log.stdout.strip():
            return float(log.stdout.strip())
    except Exception:
        pass
    return os.path.getmtime(path)

def get_diff_since_timestamp(path, timestamp):
    """Gets the diff of the file from the last commit before timestamp to workspace."""
    if not os.path.exists(path):
        return ""
    try:
        res = subprocess.run(
            ["git", "log", "-1", f"--before={int(timestamp)}", "--format=%H", "--", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            cwd=os.path.dirname(os.path.abspath(path))
        )
        commit = res.stdout.strip()
        if commit:
            diff_res = subprocess.run(
                ["git", "diff", commit, "--", path],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                cwd=os.path.dirname(os.path.abspath(path))
            )
            return diff_res.stdout
    except Exception:
        pass
    return ""

def has_toolchain_changes(diff_text):
    """Returns True if the diff text contains changes to toolchain/global options."""
    toolchain_keywords = [
        "BR2_TOOLCHAIN",
        "BR2_aarch64",
        "BR2_ARM",
        "BR2_OPTIMIZE",
        "BR2_ENABLE_LTO",
        "BR2_TARGET_LDFLAGS"
    ]
    for line in diff_text.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            if any(kw in line for kw in toolchain_keywords):
                return True
        elif line.startswith("-") and not line.startswith("---"):
            if any(kw in line for kw in toolchain_keywords):
                return True
    return False

# Paths
WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTERNAL = os.path.join(WORKSPACE, "external")

# Check version consistency
has_warnings = False

# Check if any patches under support/buildroot-patches are newer than Buildroot extraction stamp
buildroot_stamp = os.path.join(WORKSPACE, "buildroot", ".minime-buildroot-2026.05.stamp")
if os.path.exists(buildroot_stamp):
    patches_dir = os.path.join(WORKSPACE, "support", "buildroot-patches")
    if os.path.exists(patches_dir):
        patches = glob.glob(os.path.join(patches_dir, "*.patch"))
        if patches:
            newest_patch = max(get_file_mtime(p) for p in patches)
            if newest_patch > os.path.getmtime(buildroot_stamp):
                print("❌ BUILDROOT PATCHES OUT-OF-DATE: support/buildroot-patches has been updated.")
                if args.auto_clean:
                    print("🧹 Auto-cleaning: Removing buildroot directory to force re-extraction and patching...")
                    buildroot_dir = os.path.join(WORKSPACE, "buildroot")
                    if os.path.exists(buildroot_dir):
                        subprocess.run(["rm", "-rf", buildroot_dir], check=True)
                    print("✨ Clean complete. Please restart the build.")
                    sys.exit(0)
                else:
                    print("   👉 ACTION REQUIRED: Run 'make clean' or remove buildroot directory.\n")
                    has_warnings = True

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
            # Only consider board subdirectories that have a matching defconfig
            # Skip non-board outputs like panfrost-h700, dl, ccache, etc.
            defconfig = os.path.join(EXTERNAL, "configs", f"minime_{item}_defconfig")
            if not os.path.exists(defconfig):
                continue
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
        # 1a. Core defconfig files check (minime_common.config, minime_<board>.config)
        core_configs = [
            os.path.join(WORKSPACE, "external", "configs", "minime_common.config"),
            os.path.join(WORKSPACE, "external", "configs", f"minime_{board_name}.config"),
        ]
        
        toolchain_changed = False
        for f in core_configs:
            if os.path.exists(f) and get_file_mtime(f) > toolchain_stamp:
                diff_text = get_diff_since_timestamp(f, toolchain_stamp)
                if diff_text:
                    if has_toolchain_changes(diff_text):
                        print(f"❌ TOOLCHAIN CONFIG CHANGE DETECTED: {os.path.basename(f)} modified toolchain/global flags.")
                        toolchain_changed = True
                        break
                else:
                    # If we can't determine git diff, play safe if the file changed
                    toolchain_changed = True
                    break

        if toolchain_changed:
            print(f"⚠️  WARNING: Toolchain or global compiler options changed for board {board_name}!")
            if args.auto_clean:
                print(f"   🧹 Auto-cleaning: Running 'make clean BOARD={board_name}'...")
                subprocess.run(["make", "clean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                print("   ✨ Clean complete. Re-run the build to start fresh.")
                sys.exit(0)
            else:
                print("   👉 RECOMMENDED ACTION: A full rebuild is recommended ('make clean && make image')\n")
                has_warnings = True
        else:
            # Check if any core configs changed but did NOT modify toolchain settings
            for f in core_configs:
                if os.path.exists(f) and get_file_mtime(f) > toolchain_stamp:
                    print(f"ℹ️  Configuration '{os.path.basename(f)}' changed (non-toolchain). Performing incremental build.")

        # 1b. Component-specific configuration checks
        
        # Busybox config check
        busybox_config = os.path.join(WORKSPACE, "external", "board", "common", "busybox.config")
        if os.path.exists(busybox_config) and get_file_mtime(busybox_config) > toolchain_stamp:
            busybox_stamps = glob.glob(os.path.join(stamp_dir, "busybox-*", ".stamp_configured"))
            if busybox_stamps:
                busybox_stamp_time = os.path.getmtime(busybox_stamps[0])
                if get_file_mtime(busybox_config) > busybox_stamp_time:
                    print(f"❌ BUSYBOX CONFIG OUT-OF-DATE: '{os.path.basename(busybox_config)}' is newer than busybox build.")
                    if args.auto_clean:
                        print(f"   🧹 Auto-cleaning: Running 'make busybox-dirclean BOARD={board_name}'...")
                        subprocess.run(["make", "busybox-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                    else:
                        print("   👉 ACTION REQUIRED: Run 'make busybox-dirclean && make busybox'\n")
                        has_warnings = True

        # Kernel (linux) config check
        kernel_configs = [os.path.join(WORKSPACE, "external", "board", "common", "tiny-base.config")]
        board_dir = os.path.join(WORKSPACE, "external", "board", board_name)
        if os.path.exists(board_dir):
            for root, _, files in os.walk(board_dir):
                for f in files:
                    if f.endswith(".config") and "tiny-" in f:
                        kernel_configs.append(os.path.join(root, f))
                        
        kernel_stamps = glob.glob(os.path.join(stamp_dir, "linux-*", ".stamp_configured"))
        if kernel_stamps:
            kernel_stamp_time = os.path.getmtime(kernel_stamps[0])
            for kf in kernel_configs:
                if os.path.exists(kf) and get_file_mtime(kf) > toolchain_stamp:
                    if get_file_mtime(kf) > kernel_stamp_time:
                        print(f"❌ KERNEL CONFIG OUT-OF-DATE: '{os.path.basename(kf)}' is newer than kernel build.")
                        if args.auto_clean:
                            print(f"   🧹 Auto-cleaning: Running 'make linux-dirclean BOARD={board_name}'...")
                            subprocess.run(["make", "linux-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                        else:
                            print("   👉 ACTION REQUIRED: Run 'make linux-dirclean && make linux'\n")
                            has_warnings = True
                        break

        # U-Boot config check
        uboot_configs = []
        if os.path.exists(board_dir):
            for root, _, files in os.walk(board_dir):
                for f in files:
                    if f == "uboot.config":
                        uboot_configs.append(os.path.join(root, f))
                        
        uboot_stamps = glob.glob(os.path.join(stamp_dir, "uboot-*", ".stamp_configured"))
        if uboot_stamps:
            uboot_stamp_time = os.path.getmtime(uboot_stamps[0])
            for uf in uboot_configs:
                if os.path.exists(uf) and get_file_mtime(uf) > toolchain_stamp:
                    if get_file_mtime(uf) > uboot_stamp_time:
                        print(f"❌ U-BOOT CONFIG OUT-OF-DATE: '{os.path.basename(uf)}' is newer than uboot build.")
                        if args.auto_clean:
                            print(f"   🧹 Auto-cleaning: Running 'make uboot-dirclean BOARD={board_name}'...")
                            subprocess.run(["make", "uboot-dirclean", f"BOARD={board_name}"], cwd=WORKSPACE, check=True)
                        else:
                            print("   👉 ACTION REQUIRED: Run 'make uboot-dirclean && make uboot'\n")
                            has_warnings = True
                        break

    # 1b. Check for incomplete/failed package builds (Self-Healing)
    if os.path.exists(stamp_dir):
        for item in os.listdir(stamp_dir):
            item_path = os.path.join(stamp_dir, item)
            if not os.path.isdir(item_path) or item.startswith('.') or item.startswith('buildroot') or item.endswith('.tmp'):
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
            rules_newest = max(get_file_mtime(f) for f in rules_files)
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
            newest_patch = max(get_file_mtime(p) for p in patches)
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
