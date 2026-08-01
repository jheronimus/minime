# Minime Buildroot builder (amd64 native host compilation)
FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		bison \
		flex \
		unzip \
		rsync \
		git \
		curl \
		ccache \
		cmake \
		crossbuild-essential-arm64 \
		crossbuild-essential-armhf \
		swig \
		libsdl2-dev:arm64 \
		libsdl2-image-dev:arm64 \
		libsdl2-ttf-dev:arm64 \
		mold \
		zstd \
		libelf-dev \
		libssl-dev \
		bc \
		python3 \
		python3-dev \
		python3-setuptools \
		python3-pyelftools \
		u-boot-tools \
		cpio \
		genimage \
		mtools \
		dosfstools \
		lzip \
		parted \
		erofs-utils \
		file \
		wget \
		libncurses-dev \
		ca-certificates \
		sudo \
		zlib1g-dev \
		zlib1g-dev:arm64 \
	&& rm -rf /var/lib/apt/lists/*

# GitHub CLI for release uploads in CI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
		| dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null \
	&& chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
		> /etc/apt/sources.list.d/github-cli.list \
	&& apt-get update && apt-get install -y --no-install-recommends gh \
	&& rm -rf /var/lib/apt/lists/*

RUN echo "check_certificate = off" >> /etc/wgetrc

# Install Rust toolchain for cross-compiling Allium
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain nightly \
	&& chmod -R a+w $RUSTUP_HOME $CARGO_HOME \
	&& rustup target add aarch64-unknown-linux-gnu

ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd -g ${BUILDER_GID} builder 2>/dev/null || true \
	&& useradd -u ${BUILDER_UID} -g ${BUILDER_GID} -m -s /bin/bash builder \
	&& echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder \
	&& chmod 0440 /etc/sudoers.d/builder

ENV FORCE_UNSAFE_CONFIGURE=1
WORKDIR /workspace
