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

    url = manifest["url"]
    expected_sha = manifest["sha256"]
    os.makedirs(args.output_dir, exist_ok=True)

    asset = manifest.get("asset", "llvm.tar.xz")
    if args.cache_dir:
        os.makedirs(args.cache_dir, exist_ok=True)
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
