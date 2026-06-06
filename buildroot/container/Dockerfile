FROM debian:trixie

# Avoid interactive prompts during apt installations
ENV DEBIAN_FRONTEND=noninteractive

# Install complete Buildroot dependencies and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    bison \
    flex \
    gettext \
    texinfo \
    unzip \
    help2man \
    rsync \
    git \
    curl \
    ccache \
    cmake \
    mold \
    ninja-build \
    libelf-dev \
    libssl-dev \
    libedit-dev \
    bc \
    python3 \
    python3-dev \
    python3-magic \
    flake8 \
    shellcheck \
    swig \
    u-boot-tools \
    cpio \
    genimage \
    mtools \
    dosfstools \
    lzip \
    parted \
    erofs-utils \
    patchelf \
    file \
    wget \
    libncurses-dev \
    ca-certificates \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Set up locales
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create builder non-root user with UID/GID 1000:1000
RUN groupadd -g 1000 builder && \
    useradd -u 1000 -g builder -d /home/builder -m -s /bin/bash builder

RUN mkdir -p /buildroot-output /home/builder/.buildroot-ccache /home/builder/.buildroot-dl /workspace && \
    chown -R builder:builder /buildroot-output /home/builder/.buildroot-ccache /home/builder/.buildroot-dl /workspace && \
    chmod 777 /buildroot-output /home/builder/.buildroot-ccache /home/builder/.buildroot-dl /workspace

# Set ccache variables
ENV BR2_CCACHE_DIR=/buildroot-output/ccache
ENV CCACHE_DIR=/buildroot-output/ccache

USER builder
WORKDIR /workspace
