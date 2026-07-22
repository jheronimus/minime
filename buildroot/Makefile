SHELL := /bin/bash
ROOT_DIR := $(CURDIR)
OS := $(shell uname -s)

ifeq ($(OS),Darwin)
    HOMEBREW_PREFIX ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
    COREUTILS_GNUBIN := $(HOMEBREW_PREFIX)/opt/coreutils/libexec/gnubin
    ifneq ($(wildcard $(COREUTILS_GNUBIN)),)
        export PATH := $(COREUTILS_GNUBIN):$(PATH)
    endif
endif

BUILDROOT_VERSION := 2026.05.1
BUILDROOT_ARCHIVE := buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_URL := https://buildroot.org/downloads/$(BUILDROOT_ARCHIVE)
BUILDROOT_DIR := buildroot
BUILDROOT_STAMP := $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp
SUPPORTED_BOARDS := h700 rk3326 rk3566
BOARD ?= rk3566

ifeq ($(filter $(BOARD),$(SUPPORTED_BOARDS)),)
    $(error Invalid BOARD="$(BOARD)". Supported boards: $(SUPPORTED_BOARDS))
endif

LINUX_ROOT := $(ROOT_DIR)
BASE_OUTPUT_DIR := $(HOME)/buildroot-output
BUILDROOT_CCACHE_DIR := $(HOME)/.buildroot-ccache
BUILDROOT_DL_DIR := $(HOME)/.buildroot-dl

BUILDROOT_OUTPUT_DIR := $(BASE_OUTPUT_DIR)/$(BOARD)
BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := $(BOARD).config
UI ?= minui

TOPLEVEL_JLEVEL ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
LOG_DIR := $(CURDIR)/logs

BUILDROOT_MAKE_ARGS := BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(BUILDROOT_OUTPUT_DIR) BR2_CCACHE_DIR=$(BUILDROOT_CCACHE_DIR) BR2_DL_DIR=$(BUILDROOT_DL_DIR)

RUN_CMD = $(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)

export LINUX_ROOT BUILDROOT_DIR BASE_OUTPUT_DIR BUILDROOT_OUTPUT_DIR BUILDROOT_MAKE_ARGS BOARD

.PHONY: help prepare buildroot defconfig image clean clean-all copy_images check-package FORCE

help:
	@printf '%s\n' \
		"Minime Firmware Build Orchestrator" \
		"==================================" \
		"Commands:" \
		"  make defconfig     - Merge config fragments for BOARD (default: rk3566)" \
		"  make image         - Build complete bootable firmware image for BOARD" \
		"  make prepare       - Install host tools on Linux" \
		"  make check-rebuild - Scan packages for out-of-date build stamps" \
		"  make check-package CHECK_PACKAGE_FILES='path ...'" \
		"                       Run Buildroot's package linter on specified files" \
		"  make clean         - Remove compilation output for active BOARD" \
		"  make clean-all     - Remove ALL compilation outputs and delete Buildroot source tree" \
		"  make <target>      - Pass arbitrary command directly to Buildroot (e.g., make menuconfig)" \
		"" \
		"Options (override with VAR=value):" \
		"  BOARD              - Target hardware (default: rk3566, supported: $(SUPPORTED_BOARDS))" \
		"  TOPLEVEL_JLEVEL    - Number of parallel build jobs (default: auto-detected CPU cores)"

$(BUILDROOT_STAMP):
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/buildroot-fetch-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; set -o pipefail; { \
		set -e; \
		echo "Downloading Buildroot $(BUILDROOT_VERSION)..."; \
		if command -v wget >/dev/null 2>&1; then wget -q --show-progress "$(BUILDROOT_URL)"; \
		else curl -fL -o "$(BUILDROOT_ARCHIVE)" "$(BUILDROOT_URL)"; fi; \
		rm -rf $(BUILDROOT_DIR); mkdir -p $(BUILDROOT_DIR); \
		tar xf $(BUILDROOT_ARCHIVE) --strip-components=1 -C $(BUILDROOT_DIR); \
		if [ -d support/buildroot-patches ]; then \
			echo "Applying patches to Buildroot..."; \
			for p in support/buildroot-patches/*.patch; do \
				[ -e "$$p" ] || continue; \
				echo "Applying $$p..."; \
				patch -p1 -d $(BUILDROOT_DIR) < "$$p"; \
			done; \
		fi; \
		touch $(BUILDROOT_STAMP); rm -f $(BUILDROOT_ARCHIVE); \
	} 2>&1 | tee "$$LOG_FILE"

buildroot: $(BUILDROOT_STAMP)
	@echo "Buildroot $(BUILDROOT_VERSION) is ready in $(BUILDROOT_DIR)"

prepare:
	@../scripts/prepare-linux.sh

defconfig: $(BUILDROOT_STAMP) defconfig_internal

defconfig_internal:
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	set -o pipefail; \
	mkdir -p $(BUILDROOT_OUTPUT_DIR) && \
	$(BUILDROOT_DIR)/support/kconfig/merge_config.sh \
		-O $(BUILDROOT_OUTPUT_DIR) \
		-m \
		external/configs/common.config \
		external/configs/$(BOARD).config \
		external/configs/$(UI).config 2>&1 | tee "$$LOG_FILE" && \
	$(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) olddefconfig 2>&1 | tee -a "$$LOG_FILE"

image: $(BUILDROOT_STAMP) defconfig
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	set -o pipefail; $(call RUN_CMD,-j$(TOPLEVEL_JLEVEL)) 2>&1 | tee "$$LOG_FILE"
	@$(MAKE) copy_images

copy_images:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	@echo "Copying built firmware images to out/$(BOARD)/..."
	@mkdir -p $(BUILDROOT_OUTPUT_DIR)/images
	@cp -r $(BUILDROOT_OUTPUT_DIR)/images/* out/$(BOARD)/ 2>/dev/null || true

check-package:
	@if [ -z "$(CHECK_PACKAGE_FILES)" ]; then \
		echo "ERROR: set CHECK_PACKAGE_FILES='path ...'" >&2; \
		exit 1; \
	fi
	@python3 buildroot/utils/check-package $(CHECK_PACKAGE_FILES)

clean:
	@rm -rf $(LOG_DIR) out/$(BOARD)/
	@rm -rf $(BUILDROOT_OUTPUT_DIR)

clean-all:
	@rm -rf $(BUILDROOT_DIR) $(LOG_DIR) $(CURDIR)/out/
	@rm -rf $(BASE_OUTPUT_DIR)

Makefile: ;

%: $(BUILDROOT_STAMP) FORCE
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || "$@" == *xconfig || "$@" == *gconfig ]]; then \
		$(call RUN_CMD,$@); \
	else \
		set -o pipefail; $(call RUN_CMD,$@) 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
