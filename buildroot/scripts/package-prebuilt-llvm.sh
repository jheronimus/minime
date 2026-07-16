#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <buildroot-dir> <output-dir> <flavor> <buildroot-version> <revision> <asset-path>" >&2
  exit 2
fi

buildroot_dir="$1"
output_dir="$2"
flavor="$3"
buildroot_version="$4"
revision="$5"
asset_path="$6"

case "$flavor" in
  bootlin-musl|arm-glibc) ;;
  *) echo "unsupported flavor: $flavor" >&2; exit 2 ;;
esac

per_package_dir="${output_dir}/per-package"
if [[ ! -d "$per_package_dir" ]]; then
  echo "missing per-package directory: $per_package_dir" >&2
  echo "BR2_PER_PACKAGE_DIRECTORIES must be enabled before building the packages" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
payload_dir="${work_dir}/payload"
mkdir -p "${payload_dir}/packages"

packages=(
  host-llvm-cmake
  host-llvm
  host-clang
  host-libclc
  host-spirv-headers
  host-spirv-tools
  host-spirv-llvm-translator
  llvm
  clang
  libclc
  spirv-headers
  spirv-tools
  spirv-llvm-translator
)

copy_package() {
  local pkg="$1"
  local src="${per_package_dir}/${pkg}"
  if [[ ! -d "$src" && "$pkg" == host-* ]]; then
    # Some Buildroot versions keep host package output under the target package
    # basename. Keep this fallback explicit instead of silently omitting files.
    local basename_pkg="${pkg#host-}"
    [[ -d "${per_package_dir}/${basename_pkg}" ]] && src="${per_package_dir}/${basename_pkg}"
  fi

  if [[ ! -d "$src" ]]; then
    echo "warning: per-package output for ${pkg} not found" >&2
    return 0
  fi

  mkdir -p "${payload_dir}/packages/${pkg}"
  for domain in host staging target; do
    local domain_src="${src}/${domain}"
    if [[ "$domain" == "staging" && ! -d "$domain_src" ]]; then
      # With per-package directories, the staging files are installed to the
      # sysroot directory nested under host/<target-tuple>/sysroot/
      local sysroot_dir
      sysroot_dir=$(find "${src}/host" -maxdepth 2 -type d -name "sysroot" 2>/dev/null | head -n 1 || true)
      if [[ -n "$sysroot_dir" && -d "$sysroot_dir" ]]; then
        domain_src="$sysroot_dir"
      fi
    fi

    if [[ -d "$domain_src" ]]; then
      local exclude_args=()
      if [[ "$domain" == "staging" || "$domain" == "target" ]]; then
        exclude_args+=(--exclude '*.a')
      fi
      rsync -a --delete \
        --exclude '/opt/ext-toolchain/' \
        --exclude '/usr/share/man/' \
        --exclude '/usr/share/doc/' \
        "${exclude_args[@]}" \
        "${domain_src}/" "${payload_dir}/packages/${pkg}/${domain}/"
    fi
  done
}

for pkg in "${packages[@]}"; do
  copy_package "$pkg"
done

parse_make_var() {
  local file="$1"
  local var="$2"
  awk -F '=' -v var="$var" '$1 ~ "^" var "[[:space:]]*$" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$file" 2>/dev/null || true
}

llvm_major="$(parse_make_var "${buildroot_dir}/package/llvm-project/llvm-project.mk" LLVM_PROJECT_VERSION_MAJOR)"
llvm_version="$(parse_make_var "${buildroot_dir}/package/llvm-project/llvm-project.mk" LLVM_PROJECT_VERSION)"
llvm_version="${llvm_version//\$\(LLVM_PROJECT_VERSION_MAJOR\)/${llvm_major}}"
libclc_version="$(parse_make_var "${buildroot_dir}/package/llvm-project/libclc/libclc.mk" LIBCLC_VERSION)"
libclc_version="${libclc_version//\$\(LLVM_PROJECT_VERSION\)/${llvm_version}}"
spirv_tools_version="$(parse_make_var "${buildroot_dir}/package/spirv-tools/spirv-tools.mk" SPIRV_TOOLS_VERSION)"
spirv_translator_version="$(parse_make_var "${buildroot_dir}/package/spirv-llvm-translator/spirv-llvm-translator.mk" SPIRV_LLVM_TRANSLATOR_VERSION)"

cat >"${payload_dir}/manifest.json" <<EOF_MANIFEST
{
  "format": 1,
  "flavor": "${flavor}",
  "buildroot_version": "${buildroot_version}",
  "revision": "${revision}",
  "packages": {
    "llvm": "${llvm_version}",
    "clang": "${llvm_version}",
    "libclc": "${libclc_version}",
    "spirv-tools": "${spirv_tools_version}",
    "spirv-llvm-translator": "${spirv_translator_version}"
  },
  "layout": "packages/<buildroot-package>/{host,staging,target}"
}
EOF_MANIFEST

mkdir -p "$(dirname "$asset_path")"
XZ_OPT="-T0 -3" tar -C "$payload_dir" -cJf "$asset_path" .
sha256sum "$asset_path" >"${asset_path%.tar.xz}.sha256"
cp "${payload_dir}/manifest.json" "${asset_path%.tar.xz}.manifest.json"

printf 'Created %s\n' "$asset_path"
cat "${asset_path%.tar.xz}.sha256"
