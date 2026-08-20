MINIME_ROOT := $(abspath $(CURDIR)/../../..)
PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := rk3326 rk3566 h700
BOARD ?= rk3566
UI ?= minui

HOST_ARCH := $(shell uname -m)
PACKAGER_PLATFORM := linux/amd64

BUILDER_IMAGE := ghcr.io/jheronimus/minime-glibc:latest

.PHONY: help components image update clean

help:
	@printf '%s\n' \
		"Minime Buildroot targets:" \
		"  make components BOARD=rk3566    Build system components (kernel, rootfs, packages)" \
		"  make image BOARD=rk3566 UI=minui [INCLUDE_ROMS=1] Build full release SD image" \
		"  make update BOARD=rk3566 UI=minui [INCLUDE_ROMS=1] Build update tarball package" \
		"  make clean                      Remove built outputs"

# CI runs inside the builder container (GitHub container job), so build.sh
# runs directly with env vars pointing caches at the workspace. Local dev
# wraps in podman.
IN_CONTAINER := $(if $(MINIME_IN_CONTAINER),yes)

components:
	@if [ "$(IN_CONTAINER)" = "yes" ]; then \
		BOARD=$(BOARD) UI=$(UI) TEST_PACKAGES=$(TEST_PACKAGES) MINIME_ROOT=$(MINIME_ROOT) \
			$(MINIME_ROOT)/packages/components/buildroot/scripts/build.sh components; \
	else \
		mkdir -p $(HOME)/.buildroot-ccache $(HOME)/.buildroot-dl; \
		$(PODMAN_CMD) run $(PODMAN_TTY) --rm --platform linux/amd64 \
			-v $(MINIME_ROOT):/workspace \
			-v $(HOME)/.buildroot-ccache:/root/.buildroot-ccache \
			-v $(HOME)/.buildroot-dl:/root/.buildroot-dl \
			$(BUILDER_IMAGE) \
			sh -c "BOARD=$(BOARD) UI=$(UI) TEST_PACKAGES=$(TEST_PACKAGES) /workspace/packages/components/buildroot/scripts/build.sh components"; \
	fi

TARGET_NAME := buildroot

include ../common.mk

# Catch-all: forward unknown targets (defconfig, source, shell) to build.sh
%:
	@if [ -z "$(BOARD)" ]; then echo "ERROR: BOARD= is required" >&2; exit 1; fi; \
	BOARD=$(BOARD) ./scripts/build.sh "$@"
# trigger cache run
