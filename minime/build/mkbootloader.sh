#!/bin/sh
set -eu

BOARD="${1:-}"
UBOOT_VERSION="${2:-}"

if [ -z "$BOARD" ] || [ -z "$UBOOT_VERSION" ]; then
	echo "Usage: $0 <board> <uboot-version>" >&2
	exit 1
fi

ATF_VERSION="v2.15.0"
WORK_DIR="$(pwd)/build-bootloader-tmp"
mkdir -p "$WORK_DIR"

# Paths
MINIME_UBOOT_DIR="$(pwd)/minime/uboot"
MINIME_BOARD_DIR="$(pwd)/minime/boards/${BOARD}"
OUT_BL_DIR="${MINIME_UBOOT_DIR}/out/${BOARD}"
mkdir -p "$OUT_BL_DIR"

echo "Building bootloader for ${BOARD} (U-Boot ${UBOOT_VERSION}, ATF ${ATF_VERSION})..."

case "$BOARD" in
rk3326)
	# Vendor Rockchip boot chain: rkbin DDR blob + miniloader + BL31 (the same
	# chain ROCKNIX and the U-Boot docs use for px30). Upstream's source-built
	# px30 TPL/SPL DDR init is unreliable on these handhelds, so it is not used.
	UBOOT_DEFCONFIG="odroid-go2_defconfig"
	RKBIN_DIR="${MINIME_UBOOT_DIR}/out/rk3326/rkbin"
	;;
rk3566)
	UBOOT_DEFCONFIG="anbernic-rgxx3-rk3566_defconfig"
	# Uses prebuilt bl31.elf from rkbin
	;;
h700)
	# H700 supports both LPDDR4 (upstream defconfig) and LPDDR3 (custom).
	# DDR4 is the default; DDR3 binary is stored on the FAT partition
	# and swapped in by initramfs on first boot if DCDC3=1200mV.
	UBOOT_DEFCONFIG="anbernic_rg35xx_h700_defconfig"
	ATF_PLAT="sun50i_h616"
	H700_DDR3_DEFCONFIG="${MINIME_UBOOT_DIR}/config/ddr3.defconfig"
	;;
*)
	echo "Unsupported board: ${BOARD}" >&2
	exit 1
	;;
esac

# Set up compiler environment
if command -v ccache >/dev/null 2>&1; then
	CCACHE="ccache "
else
	CCACHE=""
fi

if [ "$(uname -m)" = "aarch64" ]; then
	if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
		export CROSS_COMPILE="aarch64-linux-gnu-"
	else
		export CROSS_COMPILE=""
	fi
else
	export CROSS_COMPILE="aarch64-linux-gnu-"
fi
export ARCH=arm

# 1. Build or Fetch ATF (BL31)
BL31_PATH=""
if [ "$BOARD" = "rk3566" ]; then
	echo "Using prebuilt BL31 and DDR init TPL for RK3566..."
	BL31_PATH="${MINIME_UBOOT_DIR}/out/rk3566/rkbin/bl31.elf"
	export ROCKCHIP_TPL="${MINIME_UBOOT_DIR}/out/rk3566/rkbin/rk3566_ddr_1056MHz_v1.25.bin"
elif [ "$BOARD" = "rk3326" ]; then
	echo "Using prebuilt BL31 for RK3326 (vendor boot chain)..."
	BL31_PATH="${RKBIN_DIR}/rk3326_bl31_v1.34.elf"
else
	echo "Cloning and building ATF ${ATF_VERSION} for ${ATF_PLAT}..."
	if [ ! -d "${WORK_DIR}/atf" ]; then
		git clone --depth 1 --branch "$ATF_VERSION" https://github.com/ARM-software/arm-trusted-firmware.git "${WORK_DIR}/atf"
	fi
	if [ "$BOARD" = "h700" ]; then
		echo "Applying ATF regulator patch..."
		curl -sSfL "https://github.com/ROCKNIX/distribution/raw/next/projects/Allwinner/patches/atf/0003-sunxi-Don-t-enable-referenced-regulators.patch" |
			git -C "${WORK_DIR}/atf" apply - || echo "WARNING: Failed to apply ATF patch"
	fi
	make -j"$(nproc)" -C "${WORK_DIR}/atf" PLAT="${ATF_PLAT}" DEBUG=0 bl31
	if [ "$BOARD" = "h700" ]; then
		BL31_PATH="${WORK_DIR}/atf/build/${ATF_PLAT}/release/bl31.bin"
	else
		BL31_PATH="${WORK_DIR}/atf/build/${ATF_PLAT}/release/bl31/bl31.elf"
	fi
fi

# Export BL31 path for U-Boot binman / build
export BL31="$BL31_PATH"

# 2. Build U-Boot
echo "Cloning and building U-Boot ${UBOOT_VERSION}..."
if [ ! -d "${WORK_DIR}/uboot" ]; then
	git clone --depth 1 --branch "v${UBOOT_VERSION}" https://github.com/u-boot/u-boot.git "${WORK_DIR}/uboot"
fi

# Run everything inside the U-Boot dir
(
	cd "${WORK_DIR}/uboot"
	export CROSS_COMPILE="${CCACHE}${CROSS_COMPILE}"

	if [ "$BOARD" = "h700" ]; then
		echo "Applying U-Boot MMC delay patch..."
		curl -sSfL "https://github.com/ROCKNIX/distribution/raw/next/projects/Allwinner/patches/u-boot/0015-sunxi-mmc-increase-stabilization-delay-from-1ms-to-20ms.patch" |
			git apply - || echo "WARNING: Failed to apply U-Boot MMC delay patch"
	fi

	# Apply board-specific U-Boot patches (e.g. rgxx3 fdtfile alignment so the
	# detected DTB filename matches the .minime/devices boot partition paths).
	for p in "${MINIME_BOARD_DIR}/patches/uboot/"*.patch; do
		[ -f "$p" ] || continue
		echo "Applying U-Boot board patch: $(basename "$p")"
		git apply "$p" || {
			echo "ERROR: failed to apply $(basename "$p")" >&2
			exit 1
		}
	done

	# Configure with default board defconfig
	make "${UBOOT_DEFCONFIG}"

	# Apply our config fragment(s). rk3326 adds a board fragment that forces
	# TEXT_BASE to 0x00200000 (the miniloader load address); U-Boot >= 2026.07
	# defaults it to 0x00800000 for the SPL/FIT maskrom path.
	FRAGMENTS="${MINIME_UBOOT_DIR}/config/uboot.config"
	if [ "$BOARD" = "rk3326" ]; then
		FRAGMENTS="${FRAGMENTS} ${MINIME_UBOOT_DIR}/config/uboot-rk3326.config"
	fi
	echo "Applying config fragments: ${FRAGMENTS}"
	# shellcheck disable=SC2086 # intentional word splitting of fragment paths
	./scripts/kconfig/merge_config.sh -m .config ${FRAGMENTS}
	make olddefconfig

	# Compile
	make -j"$(nproc)"
)

# 3. Stage the output binaries
echo "Staging prebuilt blobs..."
if [ "$BOARD" = "h700" ]; then
	cp -f "${WORK_DIR}/uboot/u-boot-sunxi-with-spl.bin" "${OUT_BL_DIR}/u-boot-sunxi-with-spl.bin"

	# Build DDR3 variant (LPDDR3 DRAM tuning, DCDC3=1200mV)
	if [ -n "${H700_DDR3_DEFCONFIG:-}" ] && [ -f "${H700_DDR3_DEFCONFIG}" ]; then
		echo "Building DDR3 variant..."
		(
			cd "${WORK_DIR}/uboot"
			make mrproper
			cp -f "${H700_DDR3_DEFCONFIG}" configs/anbernic_rg35xx_h700_lpddr3_defconfig
			make anbernic_rg35xx_h700_lpddr3_defconfig
			./scripts/kconfig/merge_config.sh -m .config "${MINIME_UBOOT_DIR}/config/uboot.config"
			make olddefconfig
			make -j"$(nproc)"
		)
		cp -f "${WORK_DIR}/uboot/u-boot-sunxi-with-spl.bin" "${OUT_BL_DIR}/u-boot-sunxi-with-spl-ddr3.bin"
	fi
elif [ "$BOARD" = "rk3326" ]; then
	echo "Packing RK3326 vendor boot chain (idbloader + uboot + trust)..."
	# idbloader.img = DDR init blob + miniloader, appended raw because mkimage
	# cannot pack a second stage for rk3326 (mirrors ROCKNIX rkhelper / U-Boot
	# "Package with Rockchip miniloader" docs).
	"${WORK_DIR}/uboot/tools/mkimage" -n px30 -T rksd \
		-d "${RKBIN_DIR}/rk3326_ddr_333MHz_v2.11.bin" "${WORK_DIR}/idbloader.img"
	cat "${RKBIN_DIR}/rk3326_miniloader_v1.40.bin" >>"${WORK_DIR}/idbloader.img"
	# uboot.img = U-Boot proper in Rockchip loaderimage format, loaded at 0x200000.
	"${RKBIN_DIR}/tools/loaderimage" --pack --uboot \
		"${WORK_DIR}/uboot/u-boot-dtb.bin" "${WORK_DIR}/uboot.img" 0x200000
	# trust.img = BL31 packed by trust_merger.
	cat >"${WORK_DIR}/trust.ini" <<EOF
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=${RKBIN_DIR}/rk3326_bl31_v1.34.elf
ADDR=0x00010000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=${WORK_DIR}/trust.img
EOF
	"${RKBIN_DIR}/tools/trust_merger" --verbose "${WORK_DIR}/trust.ini"
	cp -f "${WORK_DIR}/idbloader.img" "${OUT_BL_DIR}/"
	cp -f "${WORK_DIR}/uboot.img" "${OUT_BL_DIR}/"
	cp -f "${WORK_DIR}/trust.img" "${OUT_BL_DIR}/"
else
	cp -f "${WORK_DIR}/uboot/idbloader.img" "${OUT_BL_DIR}/"
	cp -f "${WORK_DIR}/uboot/u-boot.itb" "${OUT_BL_DIR}/"
fi

echo "${UBOOT_VERSION}" >"${OUT_BL_DIR}/.uboot-version"
echo "Bootloader built successfully for ${BOARD}."
