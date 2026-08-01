#!/usr/bin/env python3
import sys
import os
import re
import subprocess
import urllib.request

def curl_get(url):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            return response.read().decode('utf-8')
    except Exception as e:
        print(f"Error fetching URL {url}: {e}")
        return None

def fetch_latest_alpine_stable():
    url = "https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/linux-stable/APKBUILD"
    print(f"Fetching latest Alpine stable version from {url}...")
    content = curl_get(url)
    if content:
        m = re.search(r"^pkgver=(7\.\d+\.\d+)", content, re.MULTILINE)
        if not m:
            m = re.search(r"^pkgver=(\d+\.\d+\.\d+)", content, re.MULTILINE)
        if m:
            return m.group(1)
    return None

def compute_hash(url, hashtype):
    print(f"Downloading and computing {hashtype} hash for {url}...")
    try:
        cmd = f"curl -sSfL {url} | {hashtype}sum"
        output = subprocess.check_output(cmd, shell=True).decode("utf-8").strip()
        return output.split()[0]
    except Exception as e:
        print(f"Failed to compute hash: {e}")
        return None

def update_apkbuild(path, version):
    if not os.path.exists(path):
        print(f"Target file not found: {path}")
        return
    with open(path, "r") as f:
        content = f.read()

    # Update pkgver
    content = re.sub(r"^pkgver=.*", f"pkgver={version}", content, flags=re.MULTILINE)

    # Compute hash and update sha512sums
    major = version.split('.')[0] if '.' in version else version
    dl_url = f"https://cdn.kernel.org/pub/linux/kernel/v{major}.x/linux-{version}.tar.xz"
    dl_filename = f"linux-{version}.tar.xz"

    sha512 = compute_hash(dl_url, "sha512")
    if sha512:
        new_sha_content = f"{sha512}  {dl_filename}"
        new_sha_line = f'sha512sums="{new_sha_content}"'
        content = re.sub(r'^sha512sums="[\s\S]*?"', new_sha_line, content, flags=re.MULTILINE)

    with open(path, "w") as f:
        f.write(content)
    print(f"Updated APKBUILD at {path}")

def update_buildroot_config(path, version):
    if not os.path.exists(path):
        print(f"Target file not found: {path}")
        return
    with open(path, "r") as f:
        content = f.read()

    pattern = r'^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=".*"'
    replacement = f'BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="{version}"'
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)

    if new_content != content:
        with open(path, "w") as f:
            f.write(new_content)
        print(f"Updated {path}")
    else:
        print(f"No changes needed in {path}")

def main():
    # Root dir of minime relative to this script
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

    version = fetch_latest_alpine_stable()
    if not version:
        print("Could not resolve latest Alpine stable version.")
        sys.exit(1)

    print(f"Latest resolved kernel version: {version}")

    apkbuild_path = os.path.join(root_dir, "minime/targets/alpine/aports/tinykernel/APKBUILD")
    buildroot_config_path = os.path.join(root_dir, "minime/targets/buildroot/external/configs/common.config")

    update_apkbuild(apkbuild_path, version)
    update_buildroot_config(buildroot_config_path, version)

if __name__ == "__main__":
    main()
