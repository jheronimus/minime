MINIME_ROOT := $(abspath $(CURDIR)/../../..)
PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := rk3326 rk3566 h700
BOARD ?= rk3566
UI ?= minui

HOST_ARCH := $(shell uname -m)
PACKAGER_PLATFORM := linux/arm64

# On an arm64 host (GitHub's ubuntu-24.04-arm runner) passing --platform
# linux/arm64 makes crun reject the image with "unknown version specified".
# The host is already arm64, so omit the flag and run the image natively.
# On any other host keep --platform so the arm64 image still runs (emulated).
ifeq ($(HOST_ARCH),aarch64)
PLATFORM_ARGS :=
else ifeq ($(HOST_ARCH),arm64)
PLATFORM_ARGS :=
else
PLATFORM_ARGS := --platform $(PACKAGER_PLATFORM)
endif

BUILDER_IMAGE := ghcr.io/jheronimus/minime-musl:latest

RUN_ARGS := $(PODMAN_TTY) --rm --privileged --user 0:0 $(PLATFORM_ARGS) \
	--ulimit nofile=65536:65536 \
	-e HOME=/home/builder \
	-v $(MINIME_ROOT):/workspace \
	-v $(HOME)/alpine-output/$(BOARD):/alpine-output \
	-v $(HOME)/alpine-repos:/alpine-repos \
	-v $(HOME)/alpine-ccache:/alpine-ccache \
	-v $(HOME)/alpine-dl:/alpine-dl

.PHONY: help components image update clean

help:
	@printf '%s\n' \
		"Minime Alpine targets:" \
		"  make components BOARD=rk3566    Build system components (kernel, rootfs, APKs)" \
		"  make image BOARD=rk3566 UI=minui Build full release SD image" \
		"  make update BOARD=rk3566 UI=minui Build update tarball package" \
		"  make clean                      Remove built outputs"

# CI runs inside the builder container (GitHub container job), so the build
# scripts run directly with env vars pointing caches at the workspace.
# Local dev still wraps in podman to enter the image.
IN_CONTAINER := $(if $(MINIME_IN_CONTAINER),yes)

components:
	@if [ "$(IN_CONTAINER)" = "yes" ]; then \
		mkdir -p $(ALPINE_OUTPUT_DIR) $(ALPINE_REPO_DIR) $(ALPINE_DL_DIR) $(CCACHE_DIR) $(CURDIR)/out/$(BOARD); \
		BOARD=$(BOARD) UI=$(UI) TEST_PACKAGES=$(TEST_PACKAGES) ALPINE_DIR=$(MINIME_ROOT)/minime/targets/alpine \
			$(MINIME_ROOT)/minime/targets/alpine/scripts/build.sh components; \
	else \
		mkdir -p $(HOME)/alpine-output/$(BOARD) $(HOME)/alpine-repos $(HOME)/alpine-ccache $(HOME)/alpine-dl $(CURDIR)/out/$(BOARD); \
		$(PODMAN_CMD) run $(RUN_ARGS) $(BUILDER_IMAGE) \
			sh -c "BOARD=$(BOARD) UI=$(UI) TEST_PACKAGES=$(TEST_PACKAGES) ALPINE_DIR=/workspace/minime/targets/alpine /workspace/minime/targets/alpine/scripts/build.sh components"; \
	fi

TARGET_NAME := alpine

include ../common.mk
