# Minime Alpine builder.
#
# Builds on Alpine v3.24 (matches aports/3.24-stable) and provides:
#   - abuild/APKBUILD helpers for cross-compiling minime APKs to aarch64 musl
#   - kernel build deps for tinykernel (bison, flex, bc, pahole, perl, python3)
#   - existing image assembly tools (erofs-utils, dosfstools, mtools, parted,
#     cpio, genimage, dtc, u-boot-tools, patchelf)
#   - Buildroot's U-Boot, idbloader, ATF binaries are *not* unpacked here; the
#     build pipeline mounts the host's Buildroot output as a volume.
#
# Cross-compiler: Alpine ships `gcc-aarch64` and `binutils-aarch64` as
# first-class packages in the main x86_64 repository.  They install into
# /usr/bin/ and provide `aarch64-alpine-linux-musl-{gcc,ld,as,...}`, which
# abuild picks up automatically when CHOST=aarch64-alpine-linux-musl.
#
# We do NOT add the aarch64 sub-architecture repos: those repos serve
# aarch64 native packages via x86_64 (e.g. aarch64/x86_64/APKINDEX.tar.gz),
# which 404 against dl-cdn.alpinelinux.org because the aarch64 native
# toolchain is only meant to run inside an aarch64 chroot.  The
# cross-compiler packages are sufficient for the abuild-driven musl build.
#
# The FROM line uses a fully-qualified registry path.  htpc.local has
# unqualified-search registries disabled in /etc/containers/registries.conf;
# a short name like `alpine:3.24` would fail the build with "did not resolve
# to an alias".  `docker.io/library/alpine:3.24` is the canonical pull spec
# for the same image and bypasses the short-name check.

FROM docker.io/library/alpine:3.24

# x86_64-only repos.  The aarch64 sub-architecture repos are intentionally
# omitted; the cross-compiler packages below live in main/x86_64.
RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main"        >  /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community"   >> /etc/apk/repositories

# Toolchain + kernel + image assembly.  Each package is on a separate line
# so apk reports a precise name on a missing-package failure.  bsdtar
# is provided by libarchive-tools; rc-services is part of the openrc
# package and is not needed in the build container (only the rootfs).
RUN apk add --no-cache --no-progress \
		abuild \
		alpine-sdk \
		bash \
		bc \
		binutils-aarch64 \
		bison \
		ccache \
		cmake \
		cpio \
		curl \
		dtc \
		file \
		flex \
		gcc-aarch64 \
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
	&& echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder \
	&& chmod 0440 /etc/sudoers.d/builder

# abuild package signing key directory; the build is reproducible without
# signing, but the directory must exist or abuild errors out.
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

# Cross-toolchain from the aarch64 cross packages is rooted at
# /usr/aarch64-linux-musl; expose it so abuild can resolve CBUILD/CHOST.
ENV PATH="/usr/aarch64-linux-musl/bin:${PATH}"
ENV CCACHE_DIR=/alpine-ccache
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

USER builder
WORKDIR /workspace
