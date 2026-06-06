#!/bin/sh
set -eu

rm -f "${TARGET_DIR}/etc/modprobe.d/panfrost.conf"
rm -f "${TARGET_DIR}/etc/udev/rules.d/50-mali.rules"
rm -f "${TARGET_DIR}/etc/udev/rules.d/99-mali.rules"
rm -f "${TARGET_DIR}/etc/profile.d/mali-priority.sh"
rm -f "${TARGET_DIR}"/usr/lib/libEGL.so*
rm -f "${TARGET_DIR}"/usr/lib/libGLESv1_CM.so*
rm -f "${TARGET_DIR}"/usr/lib/libGLESv2.so*
rm -f "${TARGET_DIR}"/usr/lib/libOpenCL.so*
rm -f "${TARGET_DIR}"/usr/lib/libgbm.so*
rm -f "${TARGET_DIR}"/usr/lib/libmali*
rm -f "${TARGET_DIR}"/usr/lib/libminime_clock_shim.so*
find "${TARGET_DIR}/lib/modules" -path "*/updates/mali_kbase.ko" -delete

kernel_version="$(find "${TARGET_DIR}/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | head -n 1)"
if [ -n "${kernel_version}" ] && command -v depmod >/dev/null 2>&1; then
	depmod -a -b "${TARGET_DIR}" "${kernel_version}"
fi
