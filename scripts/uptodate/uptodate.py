#!/usr/bin/env python3
import sys
import os
import json
import re
import subprocess

PACKAGES_DIR = os.path.join(os.path.dirname(__file__), "packages")

def curl_get(url):
    try:
        cmd = ["curl", "-sSfL", url]
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8")
    except Exception as e:
        print(f"Error fetching URL {url}: {e}")
        return None

def fetch_latest_version(schema):
    stype = schema["source_type"]
    repo = schema.get("github_repo")
    
    if stype == "github_release":
        url = f"https://api.github.com/repos/{repo}/releases/latest"
        print(f"Fetching latest release from {url}...")
        res = curl_get(url)
        if res:
            try:
                data = json.loads(res)
                return data["tag_name"]
            except Exception as e:
                print(f"Failed to parse JSON from release API: {e}")
    elif stype == "github_tag":
        url = f"https://api.github.com/repos/{repo}/tags"
        print(f"Fetching latest tag from {url}...")
        res = curl_get(url)
        if res:
            try:
                data = json.loads(res)
                if isinstance(data, list) and len(data) > 0:
                    return data[0]["name"]
            except Exception as e:
                print(f"Failed to parse JSON from tags API: {e}")
    elif stype == "github_commit":
        url = f"https://api.github.com/repos/{repo}/commits?per_page=1"
        print(f"Fetching latest commit from {url}...")
        res = curl_get(url)
        if res:
            try:
                data = json.loads(res)
                if isinstance(data, list) and len(data) > 0:
                    return data[0]["sha"]
            except Exception as e:
                print(f"Failed to parse JSON from commits API: {e}")
    elif stype == "alpine_stable":
        url = "https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/linux-stable/APKBUILD"
        print(f"Fetching latest Alpine stable version from {url}...")
        content = curl_get(url)
        if content:
            m = re.search(r"^pkgver=(7\.\d+\.\d+)", content, re.MULTILINE)
            if not m:
                m = re.search(r"^pkgver=(\d+\.\d+\.\d+)", content, re.MULTILINE)
            if m:
                return m.group(1)
    
    print(f"Could not resolve version for {schema['name']}.")
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

def update_file_regex(path, pattern, replacement):
    if not os.path.exists(path):
        print(f"Target file not found: {path}")
        return
    with open(path, "r") as f:
        content = f.read()
    
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
    if new_content != content:
        with open(path, "w") as f:
            f.write(new_content)
        print(f"Updated {path}")
    else:
        print(f"No changes needed in {path}")

def update_apkbuild(path, version, target):
    if not os.path.exists(path):
        print(f"Target file not found: {path}")
        return
    with open(path, "r") as f:
        content = f.read()

    # Update pkgver
    content = re.sub(r"^pkgver=\d+\.\d+\.\d+", f"pkgver={version}", content, flags=re.MULTILINE)
    # Also handle commit shas if the version is a commit
    if len(version) == 40:
        content = re.sub(r"^pkgver=[a-fA-F0-9]{40}", f"pkgver={version}", content, flags=re.MULTILINE)

    dl_url = target.get("download_url")
    dl_filename = target.get("download_filename")
    if dl_url and dl_filename:
        formatted_url = dl_url.format(version=version)
        formatted_filename = dl_filename.format(version=version)
        
        # Calculate SHA512
        sha512 = compute_hash(formatted_url, "sha512")
        if sha512:
            new_sha_line = f'sha512sums="{sha512}  {formatted_filename}"'
            # Replace the old sha512sums line matching the filename pattern
            # For simplicity, we search for sha512sums="... [filename]"
            escaped_filename = re.escape(formatted_filename)
            escaped_filename = re.sub(r'\\\d+\\\.\\\d+\\\.\\\d+', r'.*', escaped_filename) # make version wildcard
            pattern = r'^sha512sums="[a-f0-9]{128}\s+.*"'
            # If there's a custom line, we can just replace the whole sha512sums line if it contains the filename
            content = re.sub(r'^sha512sums=".*"', new_sha_line, content, flags=re.MULTILINE)

    with open(path, "w") as f:
        f.write(content)
    print(f"Updated APKBUILD at {path}")

def update_buildroot_hash(path, version, target):
    if not os.path.exists(path):
        print(f"Target file not found: {path}")
        return
    with open(path, "r") as f:
        lines = f.readlines()

    dl_url = target.get("download_url")
    dl_filename = target.get("download_filename")
    if not (dl_url and dl_filename):
        return

    formatted_url = dl_url.format(version=version)
    formatted_filename = dl_filename.format(version=version)
    
    sha256 = compute_hash(formatted_url, "sha256")
    if not sha256:
        return

    # Find the line in the hash file that matches our filename (ignoring version)
    # e.g., dufs-0.46.0.tar.gz or fatresize_1.1.0.orig.tar.gz
    # We replace only that line!
    # Pattern to match the base name of the file
    base_name = dl_filename.split("{version}")[0]
    ext_name = dl_filename.split("{version}")[-1]

    updated = False
    new_lines = []
    for line in lines:
        if base_name in line and ext_name in line and not "cargo" in line and not "go" in line:
            new_lines.append(f"sha256  {sha256}  {formatted_filename}\n")
            updated = True
        else:
            new_lines.append(line)
            
    if not updated:
        # Append if not found
        new_lines.append(f"sha256  {sha256}  {formatted_filename}\n")

    with open(path, "w") as f:
        f.writelines(new_lines)
    print(f"Updated hash file at {path}")

def process_package(schema_path):
    with open(schema_path) as f:
        schema = json.load(f)
    
    print(f"\nProcessing package: {schema['name']}")
    version = fetch_latest_version(schema)
    if not version:
        return
    
    if schema.get("strip_v_prefix") and version.startswith("v"):
        version = version[1:]
    
    print(f"Latest resolved version: {version}")
    
    for target in schema.get("targets", []):
        path = target["path"]
        ttype = target["type"]
        
        if ttype == "regex":
            pattern = target["pattern"]
            replacement = target["replacement"].format(version=version)
            update_file_regex(path, pattern, replacement)
        elif ttype == "alpine_apkbuild":
            update_apkbuild(path, version, target)
        elif ttype == "buildroot_hash":
            update_buildroot_hash(path, version, target)

def main():
    args = sys.argv[1:]
    if args:
        for pkg in args:
            schema_path = os.path.join(PACKAGES_DIR, f"{pkg}.json")
            if os.path.exists(schema_path):
                process_package(schema_path)
            else:
                print(f"Schema not found for package: {pkg}")
    else:
        # Process all schemas
        if os.path.exists(PACKAGES_DIR):
            for filename in sorted(os.listdir(PACKAGES_DIR)):
                if filename.endswith(".json"):
                    process_package(os.path.join(PACKAGES_DIR, filename))
        else:
            print("No packages schema folder found.")

if __name__ == "__main__":
    main()
