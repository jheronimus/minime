FROM debian:trixie

# Avoid interactive prompts during apt installations
ENV DEBIAN_FRONTEND=noninteractive

# Add the LLVM apt repository for LLVM 22 and install all Buildroot
# dependencies in a single transaction.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/trixie/ llvm-toolchain-trixie-22 main" > /etc/apt/sources.list.d/llvm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    bison \
    flex \
    unzip \
    rsync \
    git \
    ccache \
    cmake \
    mold \
    zstd \
    libelf-dev \
    libssl-dev \
    libedit-dev \
    llvm-22 \
    llvm-22-dev \
    libllvm22 \
    clang-22 \
    clang-tools-22 \
    libclang1-22 \
    libclang-cpp22 \
    libclang-common-22-dev \
    libclang-22-dev \
    libclc-22-dev \
    bc \
    python3 \
    python3-dev \
    python3-magic \
    flake8 \
    shellcheck \
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
    locales \
    && rm -rf /var/lib/apt/lists/*

# Use mold as the default linker for significantly faster linking
RUN update-alternatives --install /usr/bin/ld ld /usr/bin/mold 100

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
