#!/bin/sh
# shellcheck shell=sh
# Stage 02: Assemble custom boot-stage initrd (initramfs)

set -eu

echo "Assembling custom boot-stage loop-mount initrd..."
SYSTEM_STAGE="${ROOTPATH_TMP}/system"
INITRD_STAGE="${ROOTPATH_TMP}/initrd"

mkdir -p "${INITRD_STAGE}/bin" "${INITRD_STAGE}/sbin" "${INITRD_STAGE}/lib" \
	"${INITRD_STAGE}/proc" "${INITRD_STAGE}/sys" "${INITRD_STAGE}/dev" \
	"${INITRD_STAGE}/tmp" "${INITRD_STAGE}/mnt/card" "${INITRD_STAGE}/mnt/system"

for lib_dir in lib32 lib64 usr/lib32 usr/lib64; do
	[ -L "${SYSTEM_STAGE}/${lib_dir}" ] || continue
	mkdir -p "${INITRD_STAGE}/$(dirname "${lib_dir}")"
	cp -P "${SYSTEM_STAGE}/${lib_dir}" "${INITRD_STAGE}/${lib_dir}"
done

# Copy BusyBox binary from target rootfs and create links
cp -f "${SYSTEM_STAGE}/bin/busybox" "${INITRD_STAGE}/bin/busybox"
# Shell & basic utilities
ln -sf busybox "${INITRD_STAGE}/bin/sh"
ln -sf busybox "${INITRD_STAGE}/bin/mount"
ln -sf busybox "${INITRD_STAGE}/bin/mountpoint"
ln -sf busybox "${INITRD_STAGE}/bin/umount"
ln -sf busybox "${INITRD_STAGE}/bin/sleep"
ln -sf busybox "${INITRD_STAGE}/bin/reboot"
ln -sf busybox "${INITRD_STAGE}/bin/cp"
ln -sf busybox "${INITRD_STAGE}/bin/mkdir"
ln -sf busybox "${INITRD_STAGE}/bin/rm"
ln -sf busybox "${INITRD_STAGE}/bin/cat"
ln -sf busybox "${INITRD_STAGE}/bin/echo"
ln -sf busybox "${INITRD_STAGE}/bin/dd"
ln -sf busybox "${INITRD_STAGE}/bin/grep"
ln -sf busybox "${INITRD_STAGE}/bin/sync"
ln -sf ../bin/busybox "${INITRD_STAGE}/sbin/switch_root"

copy_runtime_lib() {
	lib_name="$1"
	lib_source="$(find "${SYSTEM_STAGE}/lib" "${SYSTEM_STAGE}/usr/lib" \
		-name "${lib_name}" -print -quit)"
	[ -n "${lib_source}" ] || {
		echo "ERROR: initramfs dependency ${lib_name} is missing" >&2
		exit 1
	}
	lib_target="${INITRD_STAGE}${lib_source#"${SYSTEM_STAGE}"}"
	[ -e "${lib_target}" ] && return 0
	mkdir -p "$(dirname "${lib_target}")"
	cp -Lf "${lib_source}" "${lib_target}"
	for dependency in $("${HOST_DIR:-/usr}/bin/patchelf" --print-needed "${lib_source}"); do
		copy_runtime_lib "${dependency}"
	done
}

copy_runtime_binary() {
	binary_name="$1"
	binary_source="${SYSTEM_STAGE}/usr/sbin/${binary_name}"
	cp -f "${binary_source}" "${INITRD_STAGE}/sbin/${binary_name}"
	for dependency in $("${HOST_DIR:-/usr}/bin/patchelf" --print-needed "${binary_source}"); do
		copy_runtime_lib "${dependency}"
	done
	interpreter="$("${HOST_DIR:-/usr}/bin/patchelf" --print-interpreter "${binary_source}")"
	mkdir -p "${INITRD_STAGE}$(dirname "${interpreter}")"
	cp -Lf "${SYSTEM_STAGE}${interpreter}" "${INITRD_STAGE}${interpreter}"
}

copy_runtime_binary parted
[ -f "${SYSTEM_STAGE}/usr/sbin/partprobe" ] && copy_runtime_binary partprobe || true
copy_runtime_binary fatresize

# Install custom init script
cp -f "${MINIME_SOURCE_ROOT}/board/common/initramfs-init.sh" "${INITRD_STAGE}/init"
chmod +x "${INITRD_STAGE}/init"

# Copy optional board-specific first boot probe script if it exists
if [ -f "${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/first-boot-probe.sh" ]; then
	cp -f "${MINIME_SOURCE_ROOT}/board/${SOC_NAME}/first-boot-probe.sh" "${INITRD_STAGE}/sbin/first-boot-probe.sh"
	chmod +x "${INITRD_STAGE}/sbin/first-boot-probe.sh"
fi

# Compile the initramfs CPIO archive.
(cd "${INITRD_STAGE}" && find . | cpio -H newc -o >"${BINARIES_DIR}/initramfs")
