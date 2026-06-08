#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
	echo "Usage: $0 <buildroot-output-dir> <version> <archive-path>" >&2
	exit 1
fi

output_dir="$1"
version="$2"
archive_path="$3"
target_dir="${output_dir}/target"
staging_dir="${output_dir}/staging"
build_dir="${output_dir}/build"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT INT TERM

panfrost_lib_dir="${tmp_dir}/usr/lib/panfrost"
pkgconfig_dir="${tmp_dir}/usr/lib/pkgconfig"
include_dir="${tmp_dir}/usr/include"

mkdir -p "${panfrost_lib_dir}" "${pkgconfig_dir}" "${include_dir}"

copy_glob() {
	pattern="$1"
	set -- ${pattern}
	if [ ! -e "$1" ]; then
		echo "ERROR: required file pattern not found: ${pattern}" >&2
		exit 1
	fi
	cp -dpfr "$@" "${panfrost_lib_dir}/"
}

copy_glob "${target_dir}/usr/lib/libEGL.so"*
copy_glob "${target_dir}/usr/lib/libGLESv2.so"*
copy_glob "${target_dir}/usr/lib/libgbm.so"*

for llvm_lib in "${target_dir}"/usr/lib/libLLVM-*.so* "${target_dir}"/usr/lib/libLLVM.so.*; do
	[ -e "${llvm_lib}" ] || continue
	cp -dpfr "${llvm_lib}" "${panfrost_lib_dir}/"
done

mkdir -p "${panfrost_lib_dir}/dri"
if [ -e "${target_dir}/usr/lib/dri/panfrost_dri.so" ]; then
	cp -dpfr "${target_dir}/usr/lib/dri/panfrost_dri.so" "${panfrost_lib_dir}/dri/"
elif [ -e "${target_dir}/usr/lib/libgallium-${version%r*}.so" ]; then
	cp -dpfr "${target_dir}/usr/lib/libgallium-${version%r*}.so" "${panfrost_lib_dir}/"
	ln -s "../libgallium-${version%r*}.so" "${panfrost_lib_dir}/dri/panfrost_dri.so"
else
	echo "ERROR: neither panfrost_dri.so nor libgallium-${version%r*}.so found" >&2
	exit 1
fi

if [ -d "${target_dir}/usr/lib/gbm" ]; then
	mkdir -p "${panfrost_lib_dir}/gbm"
	cp -dpfr "${target_dir}/usr/lib/gbm/"* "${panfrost_lib_dir}/gbm/"
fi

for pc in egl.pc glesv2.pc gbm.pc; do
	if [ -f "${staging_dir}/usr/lib/pkgconfig/${pc}" ]; then
		cp -dpfr "${staging_dir}/usr/lib/pkgconfig/${pc}" "${pkgconfig_dir}/"
	fi
done

if [ ! -f "${pkgconfig_dir}/egl.pc" ]; then
	cat > "${pkgconfig_dir}/egl.pc" <<EOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: egl
Description: Mesa Panfrost EGL
Version: ${version}
Libs: -L\${libdir}/panfrost -lEGL
Cflags: -I\${includedir}
EOF
fi

if [ ! -f "${pkgconfig_dir}/glesv2.pc" ]; then
	cat > "${pkgconfig_dir}/glesv2.pc" <<EOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: glesv2
Description: Mesa Panfrost OpenGL ES 2
Version: ${version}
Libs: -L\${libdir}/panfrost -lGLESv2
Cflags: -I\${includedir}
EOF
fi

if [ ! -f "${pkgconfig_dir}/gbm.pc" ]; then
	cat > "${pkgconfig_dir}/gbm.pc" <<EOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: gbm
Description: Mesa Panfrost GBM
Version: ${version}
Libs: -L\${libdir}/panfrost -lgbm
Cflags: -I\${includedir}
EOF
fi

for path in EGL GLES GLES2 GLES3 KHR; do
	if [ -d "${staging_dir}/usr/include/${path}" ]; then
		cp -dpfr "${staging_dir}/usr/include/${path}" "${include_dir}/"
	fi
done

if [ -f "${staging_dir}/usr/include/gbm.h" ]; then
	cp -dpfr "${staging_dir}/usr/include/gbm.h" "${include_dir}/"
else
	gbm_header="$(find "${build_dir}" -path '*/src/gbm/main/gbm.h' -print -quit)"
	if [ -z "${gbm_header}" ]; then
		echo "ERROR: gbm.h not found in staging or Mesa build dir" >&2
		exit 1
	fi
	cp -dpfr "${gbm_header}" "${include_dir}/"
fi

cat > "${tmp_dir}/COPYING" <<EOF
This archive contains prebuilt Mesa Panfrost and LLVM runtime files built with the Buildroot toolchain.
See licenses/ for license texts copied from the source build trees where available.
EOF

mkdir -p "${tmp_dir}/licenses"
for package_dir in "${build_dir}/mesa3d-"* "${build_dir}/llvm-project-"* "${build_dir}/llvm-"*; do
	[ -d "${package_dir}" ] || continue
	package_name="$(basename "${package_dir}")"
	dest_dir="${tmp_dir}/licenses/${package_name}"
	mkdir -p "${dest_dir}"
	find "${package_dir}" -maxdepth 2 -type f \( \
		-name 'COPYING*' -o \
		-name 'LICENSE*' -o \
		-name 'NOTICE*' \
	\) -exec cp -dpfr {} "${dest_dir}/" \;
done

mkdir -p "$(dirname "${archive_path}")"
tar -czf "${archive_path}" -C "${tmp_dir}" .

echo "Prebuilt archive ${archive_path} created successfully."
