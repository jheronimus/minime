MINIME_ROOT := $(abspath $(CURDIR)/../../..)
PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := rk3566 h700
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
		"  make image BOARD=rk3566 UI=minui Build full release SD image" \
		"  make update BOARD=rk3566 UI=minui Build update tarball package" \
		"  make clean                      Remove built outputs"

components:
	@mkdir -p $(HOME)/.buildroot-ccache $(HOME)/.buildroot-dl
	$(PODMAN_CMD) run $(PODMAN_TTY) --rm --platform linux/amd64 \
		-v $(MINIME_ROOT):/workspace \
		-v $(HOME)/.buildroot-ccache:/root/.buildroot-ccache \
		-v $(HOME)/.buildroot-dl:/root/.buildroot-dl \
		$(BUILDER_IMAGE) \
		sh -c "BOARD=$(BOARD) UI=$(UI) /workspace/minime/targets/buildroot/scripts/build.sh components"

TARGET_NAME := buildroot

include ../common.mk

# Catch-all: forward unknown targets (defconfig, source, shell) to build.sh
%:
	@if [ -z "$(BOARD)" ]; then echo "ERROR: BOARD= is required" >&2; exit 1; fi; \
	BOARD=$(BOARD) ./scripts/build.sh "$@"
# trigger cache run
