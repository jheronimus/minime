#!/bin/sh

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd)"
POST_IMAGE="${ROOT}/external/board/common/post-image.sh"

require() {
	file="$1"
	text="$2"
	grep -Fq -- "$text" "$file" || {
		echo "missing '$text' in $file" >&2
		exit 1
	}
}

reject() {
	file="$1"
	text="$2"
	if grep -Fq -- "$text" "$file"; then
		echo "unexpected '$text' in $file" >&2
		exit 1
	fi
}

for config in "${ROOT}"/external/configs/minime_*_defconfig; do
	require "$config" "BR2_PACKAGE_FATRESIZE=y"
done

require "$POST_IMAGE" 'lib_target="${INITRD_STAGE}/lib/${lib_name}"'
require "${ROOT}/external/board/rk3566/tiny-rk3566.config" "CONFIG_PL330_DMA=y"
require "$POST_IMAGE" 'mkdir -p "${USERDATA_STAGE}/.minime/config"'
require "$POST_IMAGE" 'mkdir -p "${USERDATA_STAGE}/.ui" "${USERDATA_STAGE}/.ui/config"'
require "$POST_IMAGE" 'mkdir -p "${USERDATA_STAGE}/.cores" "${USERDATA_STAGE}/.cores/config"'
require "$POST_IMAGE" 'cp -f "${BINARIES_DIR}/Image" "${USERDATA_STAGE}/.minime/kernel"'
require "$POST_IMAGE" '"${USERDATA_STAGE}/.minime/system"'
require "$POST_IMAGE" '"${USERDATA_STAGE}/.minime/initramfs"'
require "$POST_IMAGE" 'bs=1M count=1040'
require "$POST_IMAGE" 'mkdosfs -F 32 -s 32 -n minime'
require "$POST_IMAGE" 'mattrib -i "${BINARIES_DIR}/userdata.vfat" +h'
require "$POST_IMAGE" 'parted -s -f "$DISK_DEV" resizepart 1 100%'
require "$POST_IMAGE" 'fatresize -q -f -s max "$CARD_DEV"'
reject "$POST_IMAGE" 'fdisk "$DISK_DEV"'
reject "$POST_IMAGE" 'mkdosfs -F 32 -n minime "$CARD_DEV"'
reject "$POST_IMAGE" 'VENDOR_DIR'
reject "$POST_IMAGE" '| gzip'

for board in h700 rk3326 rk3566; do
	boot="${ROOT}/external/board/${board}/boot.cmd"
	require "$boot" '.minime/kernel'
	require "$boot" '.minime/devices/'
	require "$boot" '.minime/initramfs'
	reject "$boot" '.system/'
	reject "$boot" 'tinykernel'
done

require "${ROOT}/external/package/minui/minui.mk" '$(BINARIES_DIR)/ui/.ui/bin'
require "${ROOT}/external/package/minui/minui.mk" '$(BINARIES_DIR)/ui/.cores'
require "${ROOT}/external/package/minui/minui.mk" '$(BINARIES_DIR)/ui/.ui/res'
require "${ROOT}/external/package/drkhrse_miyoo_bezels/drkhrse_miyoo_bezels.mk" \
	'$(BINARIES_DIR)/ui/.ui/bezels'

echo "SD-card layout contract passed"
