#!/usr/bin/env python3
"""Write a stable.json channel manifest for the prebuilt LLVM package.

The producer (package-prebuilt-llvm.sh) splits the assembled llvm-rN.tar.xz
archive into <=1.9 GiB chunks so each piece fits under GitHub's 2 GiB
release-asset cap, and emits parts.tsv with one row per chunk:

    <chunk-basename>\t<chunk-sha256>\t<chunk-size-in-bytes>

This helper composes that parts list with the dispatcher-supplied build
metadata into a single stable.json that fetch-prebuilt-llvm.py reads as
the channel pointer. Invoke once after `package-prebuilt-llvm.sh` runs
(normal build path) and again when recovering a `manifest_only` rebuild
(in which case --parts-tsv points at a parts.tsv downloaded from the
existing release).

When --parts-tsv is omitted or empty, the manifest is written without a
"parts" field; that matches the legacy single-asset schema and the
existing consumer (fetch-prebuilt-llvm.py) falls back to its single-asset
download path.
"""

import argparse
import json
import os
import sys


def parse_parts_tsv(path: str) -> list:
    if not path or not os.path.exists(path):
        return []
    parts = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            chunks = line.split("\t")
            if len(chunks) != 3:
                raise SystemExit(
                    f"malformed parts.tsv row (expected 3 tab-separated fields): {line!r}"
                )
            name, sha, size = chunks
            try:
                size_int = int(size)
            except ValueError as e:
                raise SystemExit(f"malformed parts.tsv size ({size!r}) on row {line!r}") from e
            parts.append({"name": name, "sha256": sha, "size": size_int})
    return parts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", required=True, help="Path to write stable.json")
    parser.add_argument("--sha256", required=True, help="Assembled archive sha256")
    parser.add_argument("--flavor", required=True)
    parser.add_argument("--buildroot-version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--url-base", required=True, help="Release download URL base (no trailing slash)")
    parser.add_argument("--asset-name", required=True, help="Assembled archive basename, e.g. llvm-r1.tar.xz")
    parser.add_argument("--parts-tsv", default="", help="Optional parts.tsv from package-prebuilt-llvm.sh")
    args = parser.parse_args()

    url_base = args.url_base.rstrip("/")
    manifest = {
        "flavor": args.flavor,
        "buildroot_version": args.buildroot_version,
        "revision": args.revision,
        "release_tag": args.release_tag,
        "asset": args.asset_name,
        "url": f"{url_base}/{args.asset_name}",
        "sha256": args.sha256,
    }
    parts = parse_parts_tsv(args.parts_tsv)
    if parts:
        for part in parts:
            part["url"] = f"{url_base}/{part['name']}"
        manifest["parts"] = parts

    os.makedirs(os.path.dirname(os.path.abspath(args.output)) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Wrote {args.output} ({len(parts)} part(s))", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())