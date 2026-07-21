SHELL := /bin/bash
ROOT_DIR := $(abspath $(CURDIR)/..)

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := rk3566 rk3326 h700
BOARD ?= rk3566
ALPINE_IMAGE_NAME := minime-builder-alpine
ALPINE_OUTPUT_DIR := $(HOME)/alpine-output/$(BOARD)
ALPINE_REPOS_DIR := $(HOME)/alpine-repos
ALPINE_CCACHE_DIR := $(HOME)/alpine-ccache
ALPINE_DL_DIR := $(HOME)/alpine-dl
ALPINE_JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
UI ?= minui
LOG_DIR := $(CURDIR)/logs
ALPINE_BUILD_LOG := $(LOG_DIR)/alpine-image-$(BOARD).log

ifeq ($(filter $(BOARD),$(SUPPORTED_BOARDS)),)
    $(error Invalid BOARD="$(BOARD)". Supported boards: $(SUPPORTED_BOARDS))
endif

RUN_ARGS := $(PODMAN_TTY) --rm --privileged --user 0:0 --platform linux/arm64 --ulimit nofile=65536:65536 \
	-e HOME=/home/builder \
	-v $(ROOT_DIR):/workspace \
	-v $(ALPINE_OUTPUT_DIR):/alpine-output \
	-v $(ALPINE_REPOS_DIR):/alpine-repos \
	-v $(ALPINE_CCACHE_DIR):/alpine-ccache \
	-v $(ALPINE_DL_DIR):/alpine-dl

.PHONY: help prepare shell image clean clean-vm

help:
	@printf '%s\n' \
		"Minime Alpine Firmware Builder" \
		"==============================" \
		"Commands:" \
		"  make image       - Build complete Alpine firmware image for BOARD" \
		"  make shell       - Open an interactive shell inside the Alpine build container" \
		"  make prepare     - Build the Alpine builder container image" \
		"  make clean       - Remove Alpine output for BOARD" \
		"  make clean-vm    - Delete the Alpine builder container image" \
		"" \
		"Options:" \
		"  BOARD            - Target hardware (default: rk3566, supported: $(SUPPORTED_BOARDS))" \
		"  ALPINE_JOBS      - Number of parallel build jobs (default: auto-detected CPU cores)"

prepare:
	@$(PODMAN_CMD) info >/dev/null 2>&1 || (echo "ERROR: $(PODMAN_CMD) daemon is not running or not accessible." >&2 && exit 1)
	@mkdir -p $(ALPINE_OUTPUT_DIR) $(ALPINE_REPOS_DIR) $(ALPINE_CCACHE_DIR) $(ALPINE_DL_DIR)
	@$(PODMAN_CMD) image inspect $(ALPINE_IMAGE_NAME) >/dev/null 2>&1 || \
		$(PODMAN_CMD) build --platform linux/arm64 \
			--build-arg BUILDER_UID=$(HOST_UID) \
			--build-arg BUILDER_GID=$(HOST_GID) \
			-t $(ALPINE_IMAGE_NAME) -f container/Dockerfile .

shell: prepare
	@$(PODMAN_CMD) run -it $(RUN_ARGS) $(ALPINE_IMAGE_NAME) /bin/sh

image: prepare
	@mkdir -p $(LOG_DIR); LOG_FILE="$(ALPINE_BUILD_LOG)"; echo "LOG=$$LOG_FILE"; \
	$(PODMAN_CMD) run $(RUN_ARGS) $(ALPINE_IMAGE_NAME) \
		sh -c "BOARD=$(BOARD) ALPINE_JOBS=$(ALPINE_JOBS) UI=$(UI) ALPINE_DIR=/workspace/alpine /workspace/alpine/scripts/build.sh all" \
		2>&1 | tee "$$LOG_FILE"
	@mkdir -p $(CURDIR)/out/$(BOARD)
	@cp -f $(ALPINE_OUTPUT_DIR)/images/minime-alpine-$(BOARD).img.xz $(CURDIR)/out/$(BOARD)/

clean:
	@rm -rf $(LOG_DIR) $(CURDIR)/out/$(BOARD) $(ALPINE_OUTPUT_DIR)

clean-vm:
	@$(PODMAN_CMD) rmi $(ALPINE_IMAGE_NAME) 2>/dev/null || true
