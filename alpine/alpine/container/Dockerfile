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
# Cross-compiler: Alpine ships aarch64 cross packages in its main/community
# repos under the `aarch64/` sub-architecture. We enable those repos and
# install `gcc-aarch64` / `binutils-aarch64` to get an aarch64-linux-musl
# targeted C/C++ toolchain alongside the x86_64 host abuild machinery.

FROM alpine:3.24

# aports "main" + "community" for the host architecture, then aarch64 sub-architecture
# for the cross-toolchain and the aarch64 versions of the system libraries.
RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main"        >  /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community"   >> /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64"     >> /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community/aarch64" >> /etc/apk/repositories

# Base + abuild + kernel + image assembly tooling
RUN apk add --no-cache --no-progress \
		abuild \
		alpine-sdk \
		bash \
		bc \
		bison \
		bsdtar \
		ccache \
		cmake \
		cpio \
		curl \
		dtc \
		file \
		flex \
		git \
		llvm \
		llvm-dev \
		m4 \
		makedepend \
		mpc1-dev \
		mpfr-dev \
		mtools \
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
		rc-services \
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
	&& apk add --no-cache --no-progress \
		binutils-aarch64 \
		gcc-aarch64 \
		gmp-dev \
		linux-headers \
		musl-dev \
	&& true

# aports requires a non-root "packager" account. Match the host UID/GID passed
# by --user so abuild-built files are owned by the host user and not root.
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

# Cache + output directories the Makefile mounts from the host. The
# `--user $(id -u):$(id -g)` flag combined with --userns=keep-id makes these
# owned by the host user on the host filesystem.
RUN mkdir -p /alpine-output /alpine-repos /alpine-ccache /alpine-dl/src \
	&& chown -R builder:builder /alpine-output /alpine-repos /alpine-ccache /alpine-dl

# Cross-toolchain from the aarch64 sub-architecture is rooted at
# /usr/aarch64-linux-musl; expose it so abuild can resolve CBUILD/CHOST.
ENV PATH="/usr/aarch64-linux-musl/bin:${PATH}"
ENV CCACHE_DIR=/alpine-ccache
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

USER builder
WORKDIR /workspace
