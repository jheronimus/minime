MINIME_ROOT := $(abspath $(CURDIR)/../../..)
ALPINE_ROOT := $(CURDIR)
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
	-v $(MINIME_ROOT):/workspace \
	-v $(ALPINE_OUTPUT_DIR):/alpine-output \
	-v $(ALPINE_REPOS_DIR):/alpine-repos \
	-v $(ALPINE_CCACHE_DIR):/alpine-ccache \
	-v $(ALPINE_DL_DIR):/alpine-dl

.PHONY: help prepare shell image clean clean-vm

help:
	@printf '%s\n' \
		"Minime Alpine targets:" \
		"  make image BOARD=rk3566 UI=minui   Build full release SD image (default: rk3566)" \
		"  make prepare                        Build the local docker image ($(ALPINE_IMAGE_NAME))" \
		"  make shell BOARD=rk3566             Launch interactive container shell" \
		"  make clean                          Remove built outputs"

prepare:
	@if ! $(PODMAN_CMD) image inspect $(ALPINE_IMAGE_NAME) >/dev/null 2>&1; then \
		echo "Building $(ALPINE_IMAGE_NAME) image..."; \
		$(PODMAN_CMD) build --platform linux/arm64 -t $(ALPINE_IMAGE_NAME) container; \
	fi

shell: prepare
	$(PODMAN_CMD) run $(RUN_ARGS) $(ALPINE_IMAGE_NAME) /bin/sh

components: prepare
	@mkdir -p $(LOG_DIR)
	$(PODMAN_CMD) run $(RUN_ARGS) $(ALPINE_IMAGE_NAME) \
		sh -c "BOARD=$(BOARD) ALPINE_JOBS=$(ALPINE_JOBS) UI=$(UI) ALPINE_DIR=/workspace/minime/targets/alpine /workspace/minime/targets/alpine/scripts/build.sh components"

image: prepare
	@mkdir -p $(LOG_DIR)
	$(PODMAN_CMD) run $(RUN_ARGS) $(ALPINE_IMAGE_NAME) \
		sh -c "BOARD=$(BOARD) ALPINE_JOBS=$(ALPINE_JOBS) UI=$(UI) ALPINE_DIR=/workspace/minime/targets/alpine /workspace/minime/targets/alpine/scripts/build.sh system-image"
	@echo "Running genimage for Alpine $(BOARD)..."
	$(MINIME_ROOT)/minime/genimage/genimage.sh \
		--target alpine \
		--board $(BOARD) \
		--input-dir $(CURDIR)/out/$(BOARD) \
		--output-dir $(CURDIR)/out/$(BOARD)
	$(MINIME_ROOT)/minime/genimage/genupdate.sh \
		--target alpine \
		--board $(BOARD) \
		--input-dir $(CURDIR)/out/$(BOARD) \
		--output-dir $(CURDIR)/out/$(BOARD)
	@if [ -f $(CURDIR)/out/$(BOARD)/minime-alpine-$(BOARD).img.xz ]; then \
		echo "Alpine image build complete: $(CURDIR)/out/$(BOARD)/minime-alpine-$(BOARD).img.xz"; \
	fi

clean:
	@rm -rf $(LOG_DIR) $(CURDIR)/out/$(BOARD) $(ALPINE_OUTPUT_DIR)

clean-vm: clean
	$(PODMAN_CMD) rmi -f $(ALPINE_IMAGE_NAME) 2>/dev/null || true
