#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# Config pairs to check
CONFIG_PAIRS = [
    ("alpine/h700", ["alpine/board/common/tiny-base.config", "alpine/board/h700/linux.config"]),
    ("alpine/rk3326", ["alpine/board/common/tiny-base.config", "alpine/board/rk3326/linux.config"]),
    ("alpine/rk3566", ["alpine/board/common/tiny-base.config", "alpine/board/rk3566/linux.config"]),
]

# Standard firmware search roots in repo
FIRMWARE_SEARCH_DIRS = [
    Path("alpine/board/common/firmware"),
    Path("alpine/board/h700/firmware"),
    Path("alpine/board/rk3326/firmware"),
    Path("alpine/board/rk3566/firmware"),
]

def find_firmware_file(fw_path):
    """
    Checks if fw_path exists under any of the FIRMWARE_SEARCH_DIRS.
    """
    for base in FIRMWARE_SEARCH_DIRS:
        if (base / fw_path).is_file():
            return True
    return False

def check_extra_firmware(config_files, label):
    """
    Extracts CONFIG_EXTRA_FIRMWARE="..." from merged config files.
    Returns list of missing firmware paths.
    """
    missing = []
    extra_fw_list = []

    for cfile in config_files:
        p = Path(cfile)
        if not p.exists():
            continue
        with open(p, "r", encoding="utf-8") as f:
            for line in f:
                line_str = line.strip()
                if line_str.startswith("CONFIG_EXTRA_FIRMWARE="):
                    val = line_str.split("=", 1)[1].strip('"\'')
                    if val:
                        extra_fw_list.extend(val.split())

    for fw in extra_fw_list:
        if not find_firmware_file(fw):
            missing.append(fw)

    return missing

def check_dts_firmware():
    """
    Scans all .dts and .dtsi files for firmware-name = "..." declarations.
    Returns dict: fw_path -> list of dts_files referencing it.
    """
    dts_fw_map = {}
    root = Path(".")
    dts_files = list(root.glob("alpine/board/**/*.dts")) + list(root.glob("alpine/board/**/*.dtsi"))
    
    fw_regex = re.compile(r'firmware-name\s*=\s*"([^"]+)"')

    for dts in dts_files:
        try:
            content = dts.read_text(encoding="utf-8", errors="ignore")
            matches = fw_regex.findall(content)
            for fw in matches:
                if fw not in dts_fw_map:
                    dts_fw_map[fw] = []
                dts_fw_map[fw].append(str(dts))
        except Exception:
            pass

    return dts_fw_map

def main():
    errors = 0
    print("Checking required firmware files across kernel configs and Device Trees...")

    # 1. Check CONFIG_EXTRA_FIRMWARE
    for label, files in CONFIG_PAIRS:
        missing = check_extra_firmware(files, label)
        if missing:
            print(f"  [ERROR] [{label}] Missing CONFIG_EXTRA_FIRMWARE file(s):")
            for m in missing:
                print(f"    - {m}")
            errors += len(missing)

    # 2. Check Device Tree firmware-name declarations
    dts_fw_map = check_dts_firmware()
    for fw, dts_sources in dts_fw_map.items():
        if not find_firmware_file(fw):
            print(f"  [ERROR] Firmware '{fw}' referenced in DTS not found in firmware directories:")
            for s in dts_sources:
                print(f"    - Referenced by {s}")
            errors += 1

    if errors > 0:
        print(f"\nFirmware validation failed with {errors} missing file(s).")
        sys.exit(1)
    else:
        print("Firmware validation passed cleanly. All required firmware files are present.")
        sys.exit(0)

if __name__ == "__main__":
    main()
