# Minime Alpine builder.
#
# Builds on Alpine v3.24.1 (matches aports/3.24-stable) and provides:
#   - abuild/APKBUILD helpers for building minime APKs natively for aarch64 musl
#   - kernel build deps for tinykernel (bison, flex, bc, pahole, perl, python3)
#   - image assembly tools (erofs-utils, dosfstools, mtools, parted,
#     cpio, genimage, dtc, u-boot-tools, patchelf)
#
# Cross-arch build: the host is x86_64, and the container runs natively as x86_64.
# abuild uses cross-compilers (gcc-aarch64, binutils-aarch64) to build aarch64 packages
# natively at host speed, installing target headers/libraries to /usr/aarch64-alpine-linux-musl.

FROM docker.io/library/alpine:3.24.1

RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/main"        >  /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.24/community"   >> /etc/apk/repositories

# Toolchain + kernel + image assembly.  Each package is on a separate
# line so apk reports a precise name on a missing-package failure.
RUN apk add --no-cache --no-progress \
		abuild \
		alpine-sdk \
		gcc-aarch64 \
		binutils-aarch64 \
		musl-dev-aarch64 \
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
# Add builder to the abuild group too: abuild-apk refuses to run as
# a non-member ('User builder is not a member of group abuild') and the
# install is required to satisfy build/host/depends.
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN addgroup -g ${BUILDER_GID} builder 2>/dev/null || true \
	&& adduser -u ${BUILDER_UID} -G builder -D -h /home/builder -s /bin/sh builder \
	&& addgroup builder abuild 2>/dev/null || true \
	&& mkdir -p /etc/sudoers.d \
	&& echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder \
	&& chmod 0440 /etc/sudoers.d/builder

# abuild package signing key directory; the build is reproducible
# without signing, but the directory must exist or abuild errors out.
# abuild-keygen -a writes a fresh key pair non-interactively and
# registers it with abuild.conf in the same -a pass.
RUN mkdir -p /home/builder/.abuild \
	&& chown -R builder:builder /home/builder/.abuild

# Generate a self-hosted abuild signing key.  This key is only used
# for the local APK repository that build.sh installs into the
# immutable rootfs; the assembled rootfs ships its public key so
# apk-add inside the running system can verify the packages.  The
# key is per-image and intentionally not shared between runs.
# abuild-keygen -a rewrites the abuild.conf with the new key paths,
# so we seed it with the non-key settings first.
RUN printf '%s\n' \
		'REPODEST="/alpine-output/packages/main"' \
		'SRCDEST="/alpine-dl/src"' \
		'BUILDDIR="/alpine-output/build"' \
		> /home/builder/.abuild/abuild.conf \
	&& su builder -s /bin/sh -c 'abuild-keygen -a -n' \
	&& cp /home/builder/.abuild/*.pub /etc/apk/keys/ \
	&& cat /home/builder/.abuild/abuild.conf

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
