#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

_RETRY_STATUSES = {429, 500, 502, 503, 504}
_RETRY_DELAYS = [1, 2, 4, 8, 16]


def _urlopen_with_retry(url: str, timeout: int = 60):
    for attempt, delay in enumerate(_RETRY_DELAYS + [None]):
        try:
            return urllib.request.urlopen(url, timeout=timeout)
        except urllib.error.HTTPError as e:
            if e.code not in _RETRY_STATUSES or delay is None:
                raise
            print(f"HTTP {e.code} fetching {url}, retrying in {delay}s (attempt {attempt + 1})", flush=True)
            time.sleep(delay)


def fetch_json(url: str) -> dict:
    with _urlopen_with_retry(url) as response:
        return json.load(response)


def download(url: str, path: str) -> None:
    with _urlopen_with_retry(url) as response, open(path, "wb") as out:
        shutil.copyfileobj(response, out, length=1024 * 1024)


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel-url", required=True)
    parser.add_argument("--buildroot-version", required=True)
    parser.add_argument("--flavor", required=True)
    parser.add_argument("--cache-dir")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    manifest = fetch_json(args.channel_url)
    for key, expected in {
        "buildroot_version": args.buildroot_version,
        "flavor": args.flavor,
    }.items():
        actual = manifest.get(key)
        if actual != expected:
            raise SystemExit(f"manifest {key} mismatch: expected {expected!r}, got {actual!r}")

    expected_sha = manifest["sha256"]
    asset = manifest.get("asset", "llvm.tar.xz")
    parts = manifest.get("parts")
    os.makedirs(args.output_dir, exist_ok=True)

    if args.cache_dir:
        os.makedirs(args.cache_dir, exist_ok=True)

    # Two paths:
    #   * parts[] present  -> multi-asset chunked download (built by
    #     package-prebuilt-llvm.sh when the assembled archive exceeded
    #     GitHub's 2 GiB release-asset cap); chunks are downloaded,
    #     verified per-chunk, then concatenated into the assembled
    #     archive and verified against the top-level sha256.
    #   * parts[] absent   -> legacy single-asset download path.
    if parts:
        cache_basedir = os.path.join(args.cache_dir, f"{expected_sha}-{asset}") if args.cache_dir \
            else tempfile.mkdtemp(prefix="minime-prebuilt-llvm.")
        os.makedirs(cache_basedir, exist_ok=True)
        archive = os.path.join(cache_basedir, asset)

        if os.path.exists(archive) and sha256(archive) == expected_sha:
            print(f"Using cached {archive}", flush=True)
        else:
            chunk_paths = []
            for part in parts:
                part_name = part["name"]
                part_url = part["url"]
                part_sha = part["sha256"]
                part_path = os.path.join(cache_basedir, part_name)

                if os.path.exists(part_path) and sha256(part_path) == part_sha:
                    print(f"Using cached {part_path}", flush=True)
                else:
                    tmp_path = f"{part_path}.tmp"
                    print(f"Downloading {part_url}", flush=True)
                    download(part_url, tmp_path)
                    actual = sha256(tmp_path)
                    if actual != part_sha:
                        raise SystemExit(
                            f"sha256 mismatch for {part_url}: expected {part_sha}, got {actual}"
                        )
                    os.replace(tmp_path, part_path)
                chunk_paths.append(part_path)

            tmp_archive = f"{archive}.tmp"
            print(f"Assembling {asset} from {len(chunk_paths)} chunk(s)...", flush=True)
            with open(tmp_archive, "wb") as out:
                for chunk_path in chunk_paths:
                    with open(chunk_path, "rb") as f:
                        shutil.copyfileobj(f, out, length=1024 * 1024)
            actual_assembled = sha256(tmp_archive)
            if actual_assembled != expected_sha:
                raise SystemExit(
                    f"assembled archive sha256 mismatch: expected {expected_sha}, got {actual_assembled}"
                )
            os.replace(tmp_archive, archive)
    else:
        url = manifest["url"]
        if args.cache_dir:
            archive = os.path.join(args.cache_dir, f"{expected_sha}-{asset}")
            if os.path.exists(archive) and sha256(archive) == expected_sha:
                print(f"Using cached {archive}", flush=True)
            else:
                tmp_archive = f"{archive}.tmp"
                print(f"Downloading {url}", flush=True)
                download(url, tmp_archive)
                actual_sha = sha256(tmp_archive)
                if actual_sha != expected_sha:
                    raise SystemExit(f"sha256 mismatch for {url}: expected {expected_sha}, got {actual_sha}")
                os.replace(tmp_archive, archive)
        else:
            tmp = tempfile.mkdtemp(prefix="minime-prebuilt-llvm.")
            archive = os.path.join(tmp, asset)
            print(f"Downloading {url}", flush=True)
            download(url, archive)
            actual_sha = sha256(archive)
            if actual_sha != expected_sha:
                raise SystemExit(f"sha256 mismatch for {url}: expected {expected_sha}, got {actual_sha}")

    print(f"Extracting {archive} to {args.output_dir}", flush=True)
    # Use tar command rather than Python's lzma path for better streaming
    # performance on large .tar.xz artifacts.
    subprocess.run(["tar", "-xJf", archive, "-C", args.output_dir], check=True)

    with open(os.path.join(args.output_dir, ".minime-prebuilt-llvm-channel.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
