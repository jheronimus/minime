#!/bin/sh
# Minime Alpine image builder.
#
# Pipeline:
#   1. Resolve the newest v3.24.x aarch64 minirootfs + verify its published
#      checksum against the official CDN.
#   2. Build local Minime APKs (cross-compiled to aarch64-linux-musl) and
#      tinykernel against the same musl libc.
#   3. Build a local aports repo, install the official Alpine base plus the
#      Minime package set, copy in the Minime SD-card UI payload.
#   4. Run the shared post-image.sh with `-d alpine` so the same EROFS +
#      initrd + genimage flow used by Buildroot produces the final image,
#      only with the distro-qualified output name `minime-alpine-<board>.img`.
#
# Environment overrides:
#   BOARD               Target board (h700, rk3326, rk3566). Required.
#   ALPINE_JOBS         Parallel build jobs (default: $(nproc)).
#   ALPINE_DIR          Path inside the container to the alpine/ source tree.
#   LINUX_ROOT          Path inside the container to the minime repo root.
#   BUILDROOT_OUTPUT_DIR Path to the host's Buildroot output (reused bootloader).

set -eu

ALPINE_BRANCH="v3.24"
ALPINE_ARCH="aarch64"
ALPINE_MINIROOTFS_BASE_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/releases/${ALPINE_ARCH}"

# Output directories (the container maps these to host-bind volumes).
ALPINE_OUTPUT_DIR="${ALPINE_OUTPUT_DIR:-/alpine-output}"
ALPINE_BUILD_DIR="${ALPINE_BUILD_DIR:-${ALPINE_OUTPUT_DIR}/build}"
ALPINE_PACKAGES_DIR="${ALPINE_PACKAGES_DIR:-${ALPINE_OUTPUT_DIR}/packages/main}"
ALPINE_REPO_DIR="${ALPINE_REPO_DIR:-${ALPINE_OUTPUT_DIR}/repo}"
ALPINE_ROOTFS_DIR="${ALPINE_ROOTFS_DIR:-${ALPINE_OUTPUT_DIR}/rootfs}"
ALPINE_DL_DIR="${ALPINE_DL_DIR:-/alpine-dl/src}"
ALPINE_CCACHE_DIR="${ALPINE_CCACHE_DIR:-/alpine-ccache}"

# Source tree roots inside the container.
ALPINE_DIR="${ALPINE_DIR:-/workspace/alpine}"
LINUX_ROOT="${LINUX_ROOT:-/workspace}"
BUILDROOT_OUTPUT_DIR="${BUILDROOT_OUTPUT_DIR:-/buildroot-output}"

BOARD="${BOARD:-rk3566}"
ALPINE_JOBS="${ALPINE_JOBS:-$(nproc 2>/dev/null || echo 4)}"

log() { printf '[alpine] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

#──────────────────────────────────────────────────────────────────────────────
# 1. Resolve + verify minirootfs
#──────────────────────────────────────────────────────────────────────────────

resolve_minirootfs() {
	mkdir -p "${ALPINE_DL_DIR}"
	mm_index="${ALPINE_DL_DIR}/.latest-releases"
	curl -fsSL --retry 3 "${ALPINE_MINIROOTFS_BASE_URL}/latest-releases.yaml" \
		-o "${mm_index}" || die "could not fetch latest-releases.yaml"

	# latest-releases.yaml is a list of release entries; the minirootfs
	# entry has flavor: alpine-minirootfs.  Each entry begins with a
	# `-` on its own line.  Inside each entry, `version:` is listed
	# before `flavor:` (so we cannot "look forward" from the flavor to
	# find the version), and `sha256:` is listed after `flavor:`.  Use
	# the `-` separator to clear per-entry state, capture the version
	# as it appears, then print the captured version when the matching
	# flavor is encountered.
	mm_version=$(awk '
		/^-[[:space:]]*$/ { in_mini = 0; mm_version = "" }
		!in_mini && /version:/ {
			sub(/^[[:space:]]*version:[[:space:]]*/, "")
			mm_version = $0
		}
		/flavor:[[:space:]]*alpine-minirootfs/ {
			if (mm_version != "") { print mm_version; exit }
		}
	' "${mm_index}") || die "no minirootfs version in latest-releases.yaml"
	mm_sha=$(awk '
		/^-[[:space:]]*$/ { in_mini = 0 }
		/flavor:[[:space:]]*alpine-minirootfs/ { in_mini = 1 }
		in_mini && /sha256:/ {
			sub(/^[[:space:]]*sha256:[[:space:]]*/, "")
			print
			exit
		}
	' "${mm_index}") || die "no minirootfs sha256 in latest-releases.yaml"

	case "${mm_version}" in
		${ALPINE_BRANCH#v}.*) ;;
		*) die "minime is locked to ${ALPINE_BRANCH}; got ${mm_version}" ;;
	esac

	mm_tar="alpine-minirootfs-${mm_version}-${ALPINE_ARCH}.tar.gz"
	mm_path="${ALPINE_DL_DIR}/${mm_tar}"
	mm_url="${ALPINE_MINIROOTFS_BASE_URL}/${mm_tar}"

	if [ ! -f "${mm_path}" ]; then
		log "downloading ${mm_url}"
		curl -fL --retry 3 -o "${mm_path}" "${mm_url}" \
			|| die "download failed: ${mm_url}"
	fi

	mm_got=$(sha256sum "${mm_path}" | awk '{print $1}')
	[ "${mm_got}" = "${mm_sha}" ] \
		|| die "minirootfs sha256 mismatch (want ${mm_sha}, got ${mm_got})"

	log "minirootfs: ${mm_version} (sha256 $(printf '%s' "${mm_got}" | cut -c1-12)…)"
	MINIROOTFS_TAR="${mm_path}"
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Build local Minime APKs
#──────────────────────────────────────────────────────────────────────────────

build_local_apks() {
	# abuild's CBUILD = host (x86_64), CHOST = aarch64-linux-musl so the
	# package's build() is invoked with the cross toolchain.  Each APKBUILD
	# opts in by setting `carch="aarch64"` and declaring `makedepends` of
	# `gcc-aarch64 binutils-aarch64 musl-dev`.
	CBUILD="$(uname -m)-alpine-linux-musl"
	CHOST="aarch64-alpine-linux-musl"
	CARCH="aarch64"
	REPODEST="${ALPINE_PACKAGES_DIR}"
	export CBUILD CHOST CARCH REPODEST

	mkdir -p "${ALPINE_PACKAGES_DIR}" "${ALPINE_BUILD_DIR}"

	# tinykernel is built separately because it drives the host kernel
	# toolchain (not the cross-compiler) and is staged into the SD image
	# directly, not installed as a rootfs package.
	build_tinykernel

	# All other local packages share one abuild run: each APKBUILD produces
	# an APK that lands in REPODEST.  Order matters: tinykernel only feeds
	# the SD payload, so the rootfs list is everything else.
	ALPINE_PKGS="allium allium-themes bootsplash drkhrse-miyoo-bezels dufs \
		fatresize libretro-common minime-overlay minui preloaded-roms \
		retroarch-cores retroarch-frontend syncthing"

	for ALPINE_PKG in ${ALPINE_PKGS}; do
		[ -d "${ALPINE_DIR}/aports/${ALPINE_PKG}" ] || die "missing aports/${ALPINE_PKG}"
		cd "${ALPINE_DIR}/aports/${ALPINE_PKG}"
		log "abuild: ${ALPINE_PKG}"
		abuild -r -P "${ALPINE_PACKAGES_DIR}" -D "${ALPINE_DL_DIR}" \
			-c -j "${ALPINE_JOBS}"
	done
}

build_tinykernel() {
	TK_APKB="${ALPINE_DIR}/aports/tinykernel/APKBUILD"
	[ -f "${TK_APKB}" ] || die "missing aports/tinykernel/APKBUILD"

	# tinykernel uses the host kernel toolchain (the aarch64 target needs
	# the cross gcc but aports' linux-stable recipe drives it via
	# kernel.org sources; we run the same source + patch stack).
	mkdir -p "${ALPINE_BUILD_DIR}/tinykernel"
	cp -a "${ALPINE_DIR}/aports/tinykernel/." "${ALPINE_BUILD_DIR}/tinykernel/"
	cd "${ALPINE_BUILD_DIR}/tinykernel"

	log "abuild: tinykernel"
	abuild -r -P "${ALPINE_PACKAGES_DIR}" -D "${ALPINE_DL_DIR}" \
		-c -j "${ALPINE_JOBS}" rootpkg

	# Stage the kernel artifacts for post-image.sh to consume.
	TK_IMG="${ALPINE_BUILD_DIR}/tinykernel/staging/Image"
	[ -f "${TK_IMG}" ] || die "tinykernel did not produce staging/Image"
	mkdir -p "${ALPINE_OUTPUT_DIR}/boot"
	cp -f "${TK_IMG}" "${ALPINE_OUTPUT_DIR}/boot/Image"
	log "tinykernel staged: ${ALPINE_OUTPUT_DIR}/boot/Image"
}

#──────────────────────────────────────────────────────────────────────────────
# 3. Assemble Alpine rootfs (minirootfs + world packages + overlay)
#──────────────────────────────────────────────────────────────────────────────

assemble_rootfs() {
	WORLD_COMMON="${ALPINE_DIR}/configs/world-common"
	WORLD_BOARD="${ALPINE_DIR}/configs/world-${BOARD}"
	[ -f "${WORLD_COMMON}" ] || die "missing ${WORLD_COMMON}"
	[ -f "${WORLD_BOARD}" ] || die "missing ${WORLD_BOARD}"

	mkdir -p "${ALPINE_ROOTFS_DIR}"
	rm -rf "${ALPINE_ROOTFS_DIR:?}/"*
	tar -xf "${MINIROOTFS_TAR}" -C "${ALPINE_ROOTFS_DIR}"

	# Build a local aports index so apk can resolve minime-overlay etc. from
	# the same repo as the official Alpine packages.
	ALPINE_REPO_BASE="${ALPINE_MINIROOTFS_BASE_URL%/releases/${ALPINE_ARCH}}"
	cat > "${ALPINE_ROOTFS_DIR}/etc/apk/repositories" <<-EOF
		${ALPINE_REPO_BASE}/main/${ALPINE_ARCH}
		${ALPINE_REPO_BASE}/community/${ALPINE_ARCH}
		/local-repo
	EOF

	# Stage the local repo (a tarball of REPODEST) inside the rootfs so
	# `apk add` inside chroot can resolve minime packages.
	mkdir -p "${ALPINE_ROOTFS_DIR}/local-repo"
	cp -a "${ALPINE_PACKAGES_DIR}/." "${ALPINE_ROOTFS_DIR}/local-repo/"
	abuild index -o "${ALPINE_ROOTFS_DIR}/local-repo/" \
		"${ALPINE_ROOTFS_DIR}/local-repo/"*.apk 2>/dev/null || true

	# Resolve the full package list and install it.  --allow-untrusted lets
	# minime-overlay install without a signature.
	WORLD_PKGS="$(cat "${WORLD_COMMON}" "${WORLD_BOARD}" | grep -v '^#' | tr '\n' ' ')"
	[ -n "${WORLD_PKGS}" ] || die "resolved package list is empty"

	cp /etc/resolv.conf "${ALPINE_ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || true
	mount --bind /proc "${ALPINE_ROOTFS_DIR}/proc"
	mount --bind /sys "${ALPINE_ROOTFS_DIR}/sys"
	mount --bind /dev "${ALPINE_ROOTFS_DIR}/dev"
	trap 'umount -lf "${ALPINE_ROOTFS_DIR}/proc" "${ALPINE_ROOTFS_DIR}/sys" "${ALPINE_ROOTFS_DIR}/dev" 2>/dev/null || true' EXIT

	apk --root "${ALPINE_ROOTFS_DIR}" \
		--repository "${ALPINE_REPO_BASE}/main/${ALPINE_ARCH}" \
		--repository "${ALPINE_REPO_BASE}/community/${ALPINE_ARCH}" \
		--repository "/local-repo" \
		add --no-cache --initdb --allow-untrusted ${WORLD_PKGS}

	# Install the board's immutable trait payload.  This is identical to
	# what Buildroot's post-build.sh copies to /usr/share/minime/traits.
	TRAITS_SRC="${LINUX_ROOT}/external/board/${BOARD}/traits"
	[ -d "${TRAITS_SRC}" ] || die "missing traits source: ${TRAITS_SRC}"
	rm -rf "${ALPINE_ROOTFS_DIR}/usr/share/minime/traits"
	mkdir -p "${ALPINE_ROOTFS_DIR}/usr/share/minime/traits"
	cp -a "${TRAITS_SRC}/." "${ALPINE_ROOTFS_DIR}/usr/share/minime/traits/"

	# Install the tinykernel modules into the immutable EROFS rootfs.
	# /lib/modules/<kver>/ is read-only on EROFS, but the modules themselves
	# are read-only too, so that is fine.  depmod has to run inside the
	# rootfs to populate modules.dep for modprobe.
	if [ -d "${ALPINE_OUTPUT_DIR}/boot/modules/lib/modules" ]; then
		cp -a "${ALPINE_OUTPUT_DIR}/boot/modules/lib/modules/." \
			"${ALPINE_ROOTFS_DIR}/lib/modules/"
		TK_KVER=$(ls "${ALPINE_ROOTFS_DIR}/lib/modules" | head -1)
		[ -n "${TK_KVER}" ] && chroot "${ALPINE_ROOTFS_DIR}" \
			/sbin/depmod -a "${TK_KVER}" 2>/dev/null || true
	fi

	umount -lf "${ALPINE_ROOTFS_DIR}/proc" "${ALPINE_ROOTFS_DIR}/sys" "${ALPINE_ROOTFS_DIR}/dev" 2>/dev/null || true
	trap - EXIT
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Run the shared image assembly path
#──────────────────────────────────────────────────────────────────────────────

assemble_image() {
	POST_IMAGE="${LINUX_ROOT}/external/board/common/post-image.sh"
	[ -x "${POST_IMAGE}" ] || die "post-image.sh is not executable"

	# Buildroot output is the source of the bootloader artifacts.  Copy
	# them into a known place the post-image.sh picks up.
	mkdir -p "${ALPINE_OUTPUT_DIR}/bootloader"
	case "${BOARD}" in
		h700)
			BL_SRC="${BUILDROOT_OUTPUT_DIR}/images/u-boot-sunxi-with-spl.bin"
			[ -f "${BL_SRC}" ] || die "missing ${BL_SRC} (run make h700-uboot first)"
			cp -f "${BL_SRC}" "${ALPINE_OUTPUT_DIR}/bootloader/u-boot-sunxi-with-spl.bin"
			;;
		rk3326|rk3566)
			BL_IDB="${BUILDROOT_OUTPUT_DIR}/images/idbloader.img"
			BL_ITB="${BUILDROOT_OUTPUT_DIR}/images/u-boot.itb"
			[ -f "${BL_IDB}" ] || die "missing ${BL_IDB} (run make image first)"
			[ -f "${BL_ITB}" ] || die "missing ${BL_ITB} (run make image first)"
			cp -f "${BL_IDB}" "${ALPINE_OUTPUT_DIR}/bootloader/idbloader.img"
			cp -f "${BL_ITB}" "${ALPINE_OUTPUT_DIR}/bootloader/u-boot.itb"
			;;
		*) die "unsupported BOARD=${BOARD}" ;;
	esac

	# Stage the kernel + boot.scr + DTBs + UI payload into BINARIES_DIR.
	IMG_BIN="${ALPINE_OUTPUT_DIR}/images"
	mkdir -p "${IMG_BIN}"
	if [ -d "${ALPINE_BUILD_DIR}/tinykernel/staging" ]; then
		cp -f "${ALPINE_BUILD_DIR}/tinykernel/staging/Image" "${IMG_BIN}/Image" 2>/dev/null || \
			cp -f "${ALPINE_OUTPUT_DIR}/boot/Image" "${IMG_BIN}/Image"
	else
		cp -f "${ALPINE_OUTPUT_DIR}/boot/Image" "${IMG_BIN}/Image"
	fi
	[ -f "${IMG_BIN}/Image" ] || die "kernel Image missing in ${ALPINE_OUTPUT_DIR}/boot/"

	# Compile boot.cmd -> boot.scr using mkimage, matching Buildroot's
	# post-build.sh recipe.
	BOOT_CMD="${LINUX_ROOT}/external/board/${BOARD}/boot.cmd"
	[ -f "${BOOT_CMD}" ] || die "missing ${BOOT_CMD}"
	mkimage -C none -A arm -T script -d "${BOOT_CMD}" "${IMG_BIN}/boot.scr"
	log "boot.scr: ${IMG_BIN}/boot.scr"

	# Copy DTBs from the tinykernel staging area or kernel build dir.
	if [ -d "${ALPINE_OUTPUT_DIR}/boot/dtbs" ]; then
		find "${ALPINE_OUTPUT_DIR}/boot/dtbs" -name '*.dtb' \
			-exec cp -f {} "${IMG_BIN}/" \;
	else
		KERN_BUILD=$(find "${ALPINE_BUILD_DIR}/tinykernel" -name 'arch' -type d 2>/dev/null | head -1)
		if [ -n "${KERN_BUILD}" ]; then
			find "${KERN_BUILD}/../arch/arm64/boot/dts" -name '*.dtb' \
				-exec cp -f {} "${IMG_BIN}/" \; 2>/dev/null || true
		fi
	fi

	# Stage the UI payload (assembled by the minui/allium/drkhrse-miyoo-
	# bezels/preloaded-roms packages via /alpine-output/boot/ui/).
	if [ -d "${ALPINE_OUTPUT_DIR}/boot/ui" ]; then
		cp -rp "${ALPINE_OUTPUT_DIR}/boot/ui" "${IMG_BIN}/ui"
	fi

	# Build a rootfs.tar that post-image.sh expects.
	(cd "${ALPINE_ROOTFS_DIR}" && tar -cf "${ALPINE_OUTPUT_DIR}/rootfs.tar" .)

	# Hand off to the shared script.  -d alpine switches to the distro-
	# qualified output name; -o redirects BINARIES_DIR to the Alpine
	# staging dir so we do not have to reuse the Buildroot path layout.
	"${POST_IMAGE}" -c "${LINUX_ROOT}/external/board/${BOARD}/genimage.cfg" \
		-d alpine -o "${ALPINE_OUTPUT_DIR}/images"

	FINAL_IMG="${ALPINE_OUTPUT_DIR}/images/minime-alpine-${BOARD}.img.gz"
	[ -f "${FINAL_IMG}" ] || die "post-image.sh did not produce ${FINAL_IMG}"
	log "image: ${FINAL_IMG}"
}

#──────────────────────────────────────────────────────────────────────────────
# Entrypoint
#──────────────────────────────────────────────────────────────────────────────

CMD="${1:-all}"
case "${CMD}" in
	all)
		resolve_minirootfs
		build_local_apks
		assemble_rootfs
		assemble_image
		;;
	minirootfs) resolve_minirootfs ;;
	apks)       build_local_apks ;;
	rootfs)     assemble_rootfs ;;
	image)      assemble_image ;;
	shell)
		exec /bin/sh
		;;
	*)
		die "unknown subcommand: ${CMD} (use all|minirootfs|apks|rootfs|image|shell)"
		;;
esac
