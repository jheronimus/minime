#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# Board config definitions: (name, list_of_fragment_paths)
CONFIG_PAIRS = [
    ("alpine/h700", ["alpine/board/common/tiny-base.config", "alpine/board/h700/tiny-h700.config"]),
    ("alpine/rk3326", ["alpine/board/common/tiny-base.config", "alpine/board/rk3326/tiny-rk3326.config"]),
    ("alpine/rk3566", ["alpine/board/common/tiny-base.config", "alpine/board/rk3566/tiny-rk3566.config"]),
]


def parse_fragment(filepath):
    """
    Parses a single kernel config fragment file.
    Returns list of tuples: (symbol, value, line_number, raw_line)
    """
    entries = []
    path = Path(filepath)
    if not path.exists():
        return entries

    with open(path, "r", encoding="utf-8") as f:
        for idx, line in enumerate(f, 1):
            line_str = line.strip()
            if not line_str or line_str.startswith("#"):
                # Check for '# CONFIG_FOO is not set'
                not_set_match = re.match(r"^#\s+(CONFIG_\w+)\s+is\s+not\s+set$", line_str)
                if not_set_match:
                    symbol = not_set_match.group(1)
                    entries.append((symbol, "n", idx, line_str))
                continue

            if "=" in line_str:
                parts = line_str.split("=", 1)
                symbol = parts[0].strip()
                val = parts[1].strip()
                entries.append((symbol, val, idx, line_str))

    return entries

def main():
    errors = 0
    warnings = 0

    print("Checking kernel configuration fragments...")

    for label, files in CONFIG_PAIRS:
        seen = {}  # symbol -> list of (file, line_num, value)

        for file_path in files:
            p = Path(file_path)
            if not p.exists():
                continue
            entries = parse_fragment(p)
            for symbol, val, line_num, raw in entries:
                if not symbol.startswith("CONFIG_"):
                    print(f"  [ERROR] [{label}] Invalid symbol name without 'CONFIG_' prefix at {file_path}:{line_num}: '{symbol}'")
                    errors += 1
                    continue

                if symbol not in seen:
                    seen[symbol] = []
                seen[symbol].append((file_path, line_num, val))

        # Check for duplicates across fragments (except explicit board overrides like firmware)
        ALLOWED_OVERRIDES = {"CONFIG_EXTRA_FIRMWARE", "CONFIG_EXTRA_FIRMWARE_DIR"}
        for symbol, locations in seen.items():
            if len(locations) > 1 and symbol not in ALLOWED_OVERRIDES:
                loc_strs = [f"{f}:{line} (val={v})" for f, line, v in locations]
                print(f"  [ERROR] [{label}] Duplicate symbol {symbol} defined in multiple locations:")
                for loc in loc_strs:
                    print(f"    - {loc}")
                errors += 1

        # Check for orphaned vendor network toggles (CONFIG_NET_VENDOR_*=y with no subdrivers)
        vendor_toggles = {sym: locs for sym, locs in seen.items() if sym.startswith("CONFIG_NET_VENDOR_") and locs[-1][2] == "y"}
        for vendor_sym in vendor_toggles:
            vendor_name = vendor_sym.replace("CONFIG_NET_VENDOR_", "")
            # Check if any subdriver for vendor_name is enabled
            has_subdriver = any(
                sym != vendor_sym and vendor_name in sym and locs[-1][2] in ("y", "m")
                for sym, locs in seen.items()
            )
            if not has_subdriver:
                loc_file, loc_line, _ = vendor_toggles[vendor_sym][-1]
                print(f"  [WARN] [{label}] Vendor toggle {vendor_sym}=y enabled at {loc_file}:{loc_line} but no subdrivers found")
                warnings += 1

    if errors > 0:
        print(f"\nKernel config validation failed with {errors} error(s) and {warnings} warning(s).")
        sys.exit(1)
    else:
        print(f"Kernel config validation passed cleanly ({warnings} warning(s)).")
        sys.exit(0)

if __name__ == "__main__":
    main()
