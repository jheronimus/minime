# Minime Buildroot builder (amd64 native host compilation)
FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
		build-essential \
		bison \
		flex \
		unzip \
		rsync \
		git \
		curl \
		ccache \
		cmake \
		mold \
		zstd \
		libelf-dev \
		libssl-dev \
		bc \
		python3 \
		python3-dev \
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
	&& rm -rf /var/lib/apt/lists/*

RUN echo "check_certificate = off" >> /etc/wgetrc

ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd -g ${BUILDER_GID} builder 2>/dev/null || true \
	&& useradd -u ${BUILDER_UID} -g ${BUILDER_GID} -m -s /bin/bash builder \
	&& echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder \
	&& chmod 0440 /etc/sudoers.d/builder

USER builder
WORKDIR /workspace
