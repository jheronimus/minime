# Minime Alpine build.
#
# Leaf makefile behind Taskfile.
# Builds the Alpine foundation for retro handhelds:
#   - components: kernel, DTBs, rootfs (system.erofs + initramfs.img)
#   - image: flashable SD card image via genimage
#   - builder: builder container

ALPINE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MINIME_ROOT := $(abspath $(ALPINE_DIR)/..)
PLATFORM := alpine

PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := h700 rk3566
BOARD ?= h700

# The builder image. Overridable so a fork can build its own.
REGISTRY_IMAGE ?= ghcr.io/jheronimus/minime-builder:latest
BUILDER_IMAGE ?= minime-alpine-builder:local

# On an arm64 host (GitHub's ubuntu-24.04-arm runner) passing --platform
# linux/arm64 makes crun reject the image with "unknown version specified".
# The host is already arm64, so omit the flag and run the image natively.
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),aarch64)
PLATFORM_ARGS :=
else ifeq ($(HOST_ARCH),arm64)
PLATFORM_ARGS :=
else
PLATFORM_ARGS := --platform linux/arm64
endif

MOUNTS := --ulimit nofile=65536:65536 -e HOME=/home/builder \
	-v $(MINIME_ROOT):/minime \
	-v $(HOME)/alpine-output/$(BOARD):/alpine-output \
	-v $(HOME)/alpine-ccache:/alpine-ccache \
	-v $(HOME)/alpine-dl:/alpine-dl

CONTAINER_ENV := -e 'CROSS_COMPILE=ccache ' -e 'CC=ccache gcc' -e 'CXX=ccache g++' \
	-e PREFIX=/usr \
	-e ARCH=aarch64 \
	-e SDKROOT=/ \
	-e BOARD=$(BOARD)

define in_container
	@mkdir -p $(HOME)/alpine-output/$(BOARD) $(HOME)/alpine-ccache $(HOME)/alpine-dl/src
	@$(PODMAN_CMD) run $(PODMAN_TTY) --rm --privileged --user 0:0 $(PLATFORM_ARGS) \
		$(MOUNTS) $(CONTAINER_ENV) $(BUILDER_IMAGE) sh -c "$(1)"
endef

.PHONY: help components image builder clean

help:
	@printf '%s\n' \
		"Minime Alpine foundation (normally invoked as: task <name>):" \
		"" \
		"  components  Build the kernel and rootfs for BOARD" \
		"  image       Package the flashable .img.zst for BOARD" \
		"  builder     Build the builder image locally" \
		"  clean       Remove built outputs"

components:
	$(call in_container,BOARD=$(BOARD) ALPINE_DIR=/minime/alpine MINIME_ROOT=/minime \
		/minime/alpine/scripts/build.sh components)

image:
	$(call in_container,/minime/alpine/image/build.sh \
		--board $(BOARD) \
		--input-dir /minime/alpine/out/$(BOARD) \
		--output-dir /minime/alpine/out/$(BOARD) \
		--payload-dir /minime/releases)

builder:
	@if [ -z "$$FORCE_BUILD_CONTAINER" ] && $(PODMAN_CMD) image inspect $(BUILDER_IMAGE) >/dev/null 2>&1; then \
		echo "Builder image $(BUILDER_IMAGE) already exists locally"; \
	elif [ -z "$$FORCE_BUILD_CONTAINER" ] && $(PODMAN_CMD) pull $(REGISTRY_IMAGE); then \
		$(PODMAN_CMD) tag $(REGISTRY_IMAGE) $(BUILDER_IMAGE); \
		echo "Pulled $(REGISTRY_IMAGE) and tagged as $(BUILDER_IMAGE)"; \
	else \
		echo "Building $(BUILDER_IMAGE) locally..."; \
		$(PODMAN_CMD) build -t $(BUILDER_IMAGE) $(PLATFORM_ARGS) $(ALPINE_DIR)/container; \
	fi

clean:
	rm -rf $(MINIME_ROOT)/releases
	rm -rf $(ALPINE_DIR)/out/$(BOARD)
