# Minime Alpine builder.
#
# Builds on Alpine v3.24 (matches aports/3.24-stable) and provides:
#   - abuild/APKBUILD helpers for building minime APKs natively for aarch64 musl
#   - kernel build deps for tinykernel (bison, flex, bc, pahole, perl, python3)
#   - existing image assembly tools (erofs-utils, dosfstools, mtools, parted,
#     cpio, genimage, dtc, u-boot-tools, patchelf)
#   - Buildroot's U-Boot, idbloader, ATF binaries are *not* unpacked here; the
#     build pipeline mounts the host's Buildroot output as a volume.
#
# Cross-arch build: the host (CI runner on htpc.local) is x86_64, but the
# builder runs as aarch64.  qemu-user-static + qemu-user-binfmt on the
# host (Debian 13 package `qemu-user-static` registers binfmt_misc for
# aarch64 transparently) lets podman run aarch64 binaries in the
# container.  All packages below are aarch64 native; abuild runs natively
# and cross-compilation is unnecessary.
#
# htpc.local's /etc/containers/registries.conf has no unqualified-search
# registries, so the FROM line uses the fully-qualified
# docker.io/library/alpine:3.24 to bypass the short-name check.

FROM --platform=linux/arm64 docker.io/library/alpine:3.24

# aarch64-native main + community repos only.  bsdtar is provided by
# libarchive-tools on Alpine 3.24 (no top-level bsdtar package).  No
# cross-compiler packages are needed; gcc/binutils default to the
# aarch64 toolchain in this image.
RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main"        >  /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community"   >> /etc/apk/repositories

# Toolchain + kernel + image assembly.  Each package is on a separate
# line so apk reports a precise name on a missing-package failure.
RUN apk add --no-cache --no-progress \
		abuild \
		alpine-sdk \
		bash \
		bc \
		bison \
		ccache \
		cmake \
		cpio \
		curl \
		dtc \
		file \
		flex \
		git \
		gmp-dev \
		libarchive-tools \
		linux-headers \
		llvm \
		llvm-dev \
		m4 \
		makedepend \
		mpc1-dev \
		mpfr-dev \
		mtools \
		musl-dev \
		ncurses-dev \
		openssl-dev \
		pahole \
		perl \
		pkgconf \
		py3-pip \
		py3-pycryptodome \
		py3-requests \
		py3-yaml \
		python3 \
		python3-dev \
		rsync \
		squashfs-tools \
		sudo \
		util-linux-dev \
		xz \
		zip \
		dosfstools \
		erofs-utils \
		u-boot-tools \
		patchelf \
		wget \
	&& true

# aports requires a non-root "packager" account.  Match the host UID/GID
# passed by --user so abuild-built files are owned by the host user.
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN addgroup -g ${BUILDER_GID} builder 2>/dev/null || true \
	&& adduser -u ${BUILDER_UID} -G builder -D -h /home/builder -s /bin/sh builder \
	&& mkdir -p /etc/sudoers.d \
	&& echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder \
	&& chmod 0440 /etc/sudoers.d/builder

# abuild package signing key directory; the build is reproducible
# without signing, but the directory must exist or abuild errors out.
RUN mkdir -p /home/builder/.abuild \
	&& printf '%s\n' \
		'PACKAGER_PRIVKEY="/home/builder/.abuild/minime.rsa"' \
		'PACKAGER_PUBKEY="/home/builder/.abuild/minime.rsa.pub"' \
		'REPODEST="/alpine-output/packages/main"' \
		'SRCDEST="/alpine-dl/src"' \
		'BUILDDIR="/alpine-output/build"' \
		> /home/builder/.abuild/abuild.conf \
	&& chown -R builder:builder /home/builder/.abuild

# Cache + output directories the Makefile mounts from the host.  The
# `--user $(id -u):$(id -g)` flag combined with --userns=keep-id makes
# these owned by the host user on the host filesystem.
RUN mkdir -p /alpine-output /alpine-repos /alpine-ccache /alpine-dl/src \
	&& chown -R builder:builder /alpine-output /alpine-repos /alpine-ccache /alpine-dl

ENV CCACHE_DIR=/alpine-ccache
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

USER builder
WORKDIR /workspace
