#!/usr/bin/env python3
import sys
import re
from pathlib import Path

HEX_64_RE = re.compile(r"^[0-9a-fA-F]{64}$")
HEX_128_RE = re.compile(r"^[0-9a-fA-F]{128}$")

def check_buildroot_hash_file(filepath):
    errors = []
    with open(filepath, "r", encoding="utf-8") as f:
        for idx, line in enumerate(f, 1):
            line_str = line.strip()
            if not line_str or line_str.startswith("#"):
                continue
            parts = line_str.split()
            if len(parts) >= 3:
                algo = parts[0].lower()
                hash_val = parts[1]
                if algo == "sha256":
                    if not HEX_64_RE.match(hash_val):
                        errors.append(f"{filepath}:{idx}: Invalid SHA-256 hash length/format '{hash_val}' (expected 64 hex chars)")
                elif algo == "sha512":
                    if not HEX_128_RE.match(hash_val):
                        errors.append(f"{filepath}:{idx}: Invalid SHA-512 hash length/format '{hash_val}' (expected 128 hex chars)")
    return errors

def check_apkbuild_file(filepath):
    errors = []
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # Match sha512sums="..." or sha256sums="..." blocks
    for match in re.finditer(r"(sha256sums|sha512sums)=[\"\'](.*?)[\"\']", content, re.DOTALL):
        algo_type = match.group(1)
        hashes_str = match.group(2)
        tokens = hashes_str.split()
        for token in tokens:
            token_clean = token.strip('"\'')
            if not token_clean or token_clean == "SKIP":
                continue
            if algo_type == "sha256" and not HEX_64_RE.match(token_clean):
                errors.append(f"{filepath}: Invalid SHA-256 string in {algo_type}: '{token_clean}'")
            elif algo_type == "sha512" and not HEX_128_RE.match(token_clean):
                errors.append(f"{filepath}: Invalid SHA-512 string in {algo_type}: '{token_clean}'")

    return errors

def main():
    root_dir = Path(".")
    all_errors = []

    # Check Buildroot .hash files
    br_hashes = list(root_dir.glob("buildroot/external/package/*/*.hash"))
    print(f"Checking {len(br_hashes)} Buildroot package .hash file(s)...")
    for bh in br_hashes:
        all_errors.extend(check_buildroot_hash_file(bh))

    # Check Alpine APKBUILD files
    apkbuilds = list(root_dir.glob("alpine/aports/*/APKBUILD"))
    print(f"Checking {len(apkbuilds)} Alpine APKBUILD file(s)...")
    for ak in apkbuilds:
        all_errors.extend(check_apkbuild_file(ak))

    if all_errors:
        print(f"\n[ERROR] Found {len(all_errors)} hash validation error(s):")
        for err in all_errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("Hash validation passed cleanly. All SHA-256 and SHA-512 strings are valid.")
        sys.exit(0)

if __name__ == "__main__":
    main()
