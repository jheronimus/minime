#!/usr/bin/env python3
"""Verify that the common section of all Minime board defconfigs is identical.

Each defconfig in external/configs/minime_<board>_defconfig must contain a block
starting with the "# Common section" header and ending with the
"# Platform specific section" header.  The extracted common blocks (order and
content) must be byte-for-byte identical across all boards.
"""
import os
import sys

WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIGS_DIR = os.path.join(WORKSPACE, "external", "configs")
BOARDS = ("h700", "rk3326", "rk3566")

COMMON_START = "# Common section:"
COMMON_END = "# Platform specific section:"


def extract_common(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    start = None
    end = None
    for i, line in enumerate(lines):
        if line.startswith(COMMON_START):
            start = i
        elif line.startswith(COMMON_END):
            end = i
            break

    if start is None:
        raise RuntimeError(f"{path}: missing common section header")
    if end is None:
        raise RuntimeError(f"{path}: missing platform-specific section header")

    return "".join(lines[start:end])


def main():
    blocks = {}
    for board in BOARDS:
        path = os.path.join(CONFIGS_DIR, f"minime_{board}_defconfig")
        if not os.path.exists(path):
            print(f"ERROR: missing defconfig {path}")
            return 1
        blocks[board] = extract_common(path)

    reference = blocks[BOARDS[0]]
    failed = False
    for board in BOARDS[1:]:
        if blocks[board] != reference:
            failed = True
            print(f"ERROR: common section mismatch between {BOARDS[0]} and {board}")

    if failed:
        print("ERROR: common sections are not identical across all boards")
        return 1

    print("OK: common sections are identical across all boards")
    return 0


if __name__ == "__main__":
    sys.exit(main())
