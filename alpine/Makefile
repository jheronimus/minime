SHELL := /bin/bash
ROOT_DIR := $(CURDIR)
OS := $(shell uname -s)

USE_DOCKER ?= 0
ifeq ($(OS),Darwin)
    USE_DOCKER := 1
endif

DOCKER_IMAGE := minime-builder
DOCKER_TTY := $(shell tty -s && echo "-it" || echo "-i")
DOCKER_RUN_ARGS := $(DOCKER_TTY) --rm \
    -v $(ROOT_DIR):/workspace \
    -v minime-buildroot-output:/buildroot-output \
    -v minime-buildroot-ccache:/home/builder/.buildroot-ccache \
    -v minime-buildroot-dl:/home/builder/.buildroot-dl \
    --user 1000:1000

BUILDROOT_VERSION := 2026.02.2
BUILDROOT_ARCHIVE := buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_URL := https://buildroot.org/downloads/$(BUILDROOT_ARCHIVE)
BUILDROOT_DIR := buildroot
BUILDROOT_STAMP := $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp
SUPPORTED_BOARDS := h700 rk3326 rk3566
BOARD ?= h700

ifeq ($(filter $(BOARD),$(SUPPORTED_BOARDS)),)
    $(error Invalid BOARD="$(BOARD)". Supported boards: $(SUPPORTED_BOARDS))
endif

ifeq ($(USE_DOCKER),1)
    LINUX_ROOT := /workspace
    BASE_OUTPUT_DIR := /buildroot-output
    BUILDROOT_CCACHE_DIR := /home/builder/.buildroot-ccache
else
    LINUX_ROOT := $(ROOT_DIR)
    BASE_OUTPUT_DIR := $(HOME)/buildroot-output
    BUILDROOT_CCACHE_DIR := $(HOME)/.buildroot-ccache
endif

BUILDROOT_OUTPUT_DIR := $(BASE_OUTPUT_DIR)/$(BOARD)
BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := minime_$(BOARD)_defconfig

TOPLEVEL_JLEVEL ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
LOG_DIR := $(CURDIR)/logs

BUILDROOT_MAKE_ARGS := BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(BUILDROOT_OUTPUT_DIR) BR2_CCACHE_DIR=$(BUILDROOT_CCACHE_DIR)

ifeq ($(USE_DOCKER),1)
    RUN_CMD = docker run $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) make -C /workspace/$(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)
else
    RUN_CMD = $(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)
endif

export LINUX_ROOT BUILDROOT_DIR BASE_OUTPUT_DIR BUILDROOT_OUTPUT_DIR BUILDROOT_MAKE_ARGS BOARD USE_DOCKER

.PHONY: help prepare shell buildroot defconfig image clean clean-all clean-vm copy_images prepare_vm check-rebuild FORCE

help:
	@printf '%s\n' \
		"minime firmware build orchestrator:" \
		"  make prepare       - Build builder Docker image (macOS) or provision host (Linux)" \
		"  make shell         - Open an interactive terminal shell inside the environment" \
		"  make defconfig     - Apply $(MINIME_DEFCONFIG) (override with BOARD=...)" \
		"  make image         - Build complete bootable firmware image for active board" \
		"  make check-rebuild - Scan custom packages for out-of-date build stamps" \
		"  make clean         - Remove active board outputs and buildroot state" \
		"  make clean-all     - Remove ALL board outputs and buildroot state" \
		"  make clean-vm      - Delete Docker volumes and container images" \
		"  make <target>      - Pass target directly to Buildroot" \
		"" \
		"Supported boards: $(SUPPORTED_BOARDS) (selected via BOARD=..., default: h700)"

$(BUILDROOT_STAMP):
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/buildroot-fetch-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; set -o pipefail; { \
		set -e; \
		echo "Downloading Buildroot $(BUILDROOT_VERSION)..."; \
		if command -v wget >/dev/null 2>&1; then wget -q --show-progress "$(BUILDROOT_URL)"; \
		else curl -fL -o "$(BUILDROOT_ARCHIVE)" "$(BUILDROOT_URL)"; fi; \
		rm -rf $(BUILDROOT_DIR); mkdir -p $(BUILDROOT_DIR); \
		tar xf $(BUILDROOT_ARCHIVE) --strip-components=1 -C $(BUILDROOT_DIR); \
		touch $(BUILDROOT_STAMP); rm -f $(BUILDROOT_ARCHIVE); \
	} 2>&1 | tee "$$LOG_FILE"

buildroot: $(BUILDROOT_STAMP)
	@echo "Buildroot $(BUILDROOT_VERSION) is ready in $(BUILDROOT_DIR)"

prepare_vm:
ifeq ($(USE_DOCKER),1)
	@docker info >/dev/null 2>&1 || (echo "ERROR: Docker daemon is not running. Please start Colima or Docker first." >&2 && exit 1)
	@docker image inspect $(DOCKER_IMAGE) >/dev/null 2>&1 || $(MAKE) prepare
endif

prepare:
ifeq ($(USE_DOCKER),1)
	@echo "Building Docker image '$(DOCKER_IMAGE)'..."
	@docker build -t $(DOCKER_IMAGE) -f docker/Dockerfile .
else
	@./scripts/prepare-linux.sh
endif

shell: prepare_vm
ifeq ($(USE_DOCKER),1)
	@docker run -it $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) /bin/bash
else
	@bash
endif

defconfig: $(BUILDROOT_STAMP) prepare_vm
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	$(call RUN_CMD,$(MINIME_DEFCONFIG)) 2>&1 | tee "$$LOG_FILE"

image: $(BUILDROOT_STAMP) prepare_vm
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	$(call RUN_CMD,-j$(TOPLEVEL_JLEVEL)) 2>&1 | tee "$$LOG_FILE"
	@$(MAKE) copy_images

copy_images:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	@echo "Copying built firmware images to out/$(BOARD)/..."
ifeq ($(USE_DOCKER),1)
	@docker run $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) sh -c "mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(LINUX_ROOT)/out/$(BOARD)/ 2>/dev/null || true"
else
	@mkdir -p $(BUILDROOT_OUTPUT_DIR)/images
	@cp -r $(BUILDROOT_OUTPUT_DIR)/images/* out/$(BOARD)/ 2>/dev/null || true
endif

check-rebuild: prepare_vm
ifeq ($(USE_DOCKER),1)
	@docker run $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) python3 /workspace/scripts/check_rebuild.py
else
	@python3 scripts/check_rebuild.py
endif

clean:
	@rm -rf $(BUILDROOT_DIR) $(LOG_DIR) out/$(BOARD)/
ifeq ($(USE_DOCKER),1)
	@docker run $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) rm -rf $(BUILDROOT_OUTPUT_DIR) 2>/dev/null || true
else
	@rm -rf $(BUILDROOT_OUTPUT_DIR)
endif

clean-all: clean
	@rm -rf $(CURDIR)/out/
ifeq ($(USE_DOCKER),1)
	@docker run $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE) rm -rf $(BASE_OUTPUT_DIR) 2>/dev/null || true
else
	@rm -rf $(BASE_OUTPUT_DIR)
endif

clean-vm:
ifeq ($(USE_DOCKER),1)
	@echo "Deleting Docker named volumes and build image..."
	@docker volume rm minime-buildroot-output minime-buildroot-ccache minime-buildroot-dl 2>/dev/null || true
	@docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
else
	@echo "clean-vm is only applicable when using Docker." >&2
endif

Makefile: ;

%: $(BUILDROOT_STAMP) prepare_vm FORCE
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || "$@" == *xconfig || "$@" == *gconfig ]]; then \
		$(call RUN_CMD,$@); \
	else \
		$(call RUN_CMD,$@) 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
