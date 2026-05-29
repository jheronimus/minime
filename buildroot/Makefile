SHELL := /bin/bash
ROOT_DIR := $(CURDIR)
OS := $(shell uname -s)

ORB_MACHINE ?= builder
ORB_DISTRO ?= debian:trixie
ORB_ARCH ?= arm64
ORB_USER ?= $(shell id -un 2>/dev/null || printf '%s\n' builder)

BUILDROOT_VERSION := 2026.02.2
BUILDROOT_ARCHIVE := buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_URL := https://buildroot.org/downloads/$(BUILDROOT_ARCHIVE)
BUILDROOT_DIR := buildroot
BUILDROOT_STAMP := \
    $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp

ifeq ($(OS),Darwin)
    LINUX_ROOT := /mnt/mac$(ROOT_DIR)
    BUILDROOT_OUTPUT_DIR := /home/$(ORB_USER)/buildroot-output
    RUN_CMD = ./scripts/mac/run.sh "make $(BUILDROOT_MAKE_ARGS) $(1)"
else
    LINUX_ROOT := $(ROOT_DIR)
    BUILDROOT_OUTPUT_DIR := $(HOME)/buildroot-output
    RUN_CMD = $(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)
endif

BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := minime_defconfig

TOPLEVEL_JLEVEL ?= \
    $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || \
        nproc 2>/dev/null || \
        sysctl -n hw.ncpu 2>/dev/null || \
        echo 4)

LOG_DIR := $(CURDIR)/logs

BUILDROOT_MAKE_ARGS := \
    BR2_EXTERNAL=$(BR2_EXTERNAL) \
    O=$(BUILDROOT_OUTPUT_DIR)

export ORB_MACHINE \
       ORB_USER \
       LINUX_ROOT \
       BUILDROOT_DIR \
       BUILDROOT_OUTPUT_DIR \
       BUILDROOT_MAKE_ARGS

.PHONY: help prepare shell buildroot defconfig image clean clean-vm \
        copy_images prepare_vm FORCE

help:
	@printf '%s\n' \
		"minime firmware build orchestrator:" \
		"  make prepare    - Provision host (Linux) or VM (macOS)" \
		"  make shell      - Open a terminal shell" \
		"  make defconfig  - Apply $(MINIME_DEFCONFIG)" \
		"  make image      - Build complete bootable firmware image" \
		"  make clean      - Remove out/ and buildroot directories" \
		"  make clean-vm   - Delete OrbStack VM (macOS)" \
		"  make <target>   - Pass target directly to Buildroot"

$(BUILDROOT_STAMP):
	@mkdir -p $(LOG_DIR); \
	LOG_FILE="$(LOG_DIR)/buildroot-fetch-$$(date +%F-%H%M%S).log"; \
	echo "LOG=$$LOG_FILE"; \
	set -o pipefail; { \
		set -e; \
		echo "Downloading Buildroot $(BUILDROOT_VERSION)..."; \
		if command -v wget >/dev/null 2>&1; then \
			wget -q --show-progress "$(BUILDROOT_URL)"; \
		else \
			curl -fL -o "$(BUILDROOT_ARCHIVE)" "$(BUILDROOT_URL)"; \
		fi; \
		rm -rf $(BUILDROOT_DIR); \
		mkdir -p $(BUILDROOT_DIR); \
		tar xf $(BUILDROOT_ARCHIVE) --strip-components=1 \
			-C $(BUILDROOT_DIR); \
		touch $(BUILDROOT_STAMP); \
		rm -f $(BUILDROOT_ARCHIVE); \
	} 2>&1 | tee "$$LOG_FILE"

buildroot: $(BUILDROOT_STAMP)
	@echo "Buildroot $(BUILDROOT_VERSION) is ready in $(BUILDROOT_DIR)"

prepare_vm:
ifeq ($(OS),Darwin)
	@orb list --running --quiet 2>/dev/null | \
		grep -qx '$(ORB_MACHINE)' || \
		./scripts/mac/prepare.sh
endif

prepare:
ifeq ($(OS),Darwin)
	@./scripts/mac/prepare.sh
else
	@./scripts/prepare-linux.sh
endif

shell: prepare_vm
ifeq ($(OS),Darwin)
	@orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)' sh
else
	@bash
endif

defconfig: $(BUILDROOT_STAMP) prepare_vm
	@mkdir -p $(LOG_DIR); \
	LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; \
	echo "LOG=$$LOG_FILE"; \
	$(call RUN_CMD,$(MINIME_DEFCONFIG)) 2>&1 | tee "$$LOG_FILE"

image: $(BUILDROOT_STAMP) prepare_vm
	@mkdir -p $(LOG_DIR); \
	LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; \
	echo "LOG=$$LOG_FILE"; \
	$(call RUN_CMD,-j$(TOPLEVEL_JLEVEL)) 2>&1 | tee "$$LOG_FILE"
	@$(MAKE) copy_images

copy_images:
	@mkdir -p $(CURDIR)/out
	@echo "Copying built firmware images to out/..."
ifeq ($(OS),Darwin)
	@orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -lc \
		"mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && \
		cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(LINUX_ROOT)/out/ \
		2>/dev/null || true"
else
	@mkdir -p $(BUILDROOT_OUTPUT_DIR)/images
	@cp -r $(BUILDROOT_OUTPUT_DIR)/images/* out/ 2>/dev/null || true
endif

clean:
	@rm -rf $(BUILDROOT_DIR) $(LOG_DIR) out/
ifeq ($(OS),Darwin)
	@command -v orb >/dev/null 2>&1 && \
		orb list --running --quiet 2>/dev/null | \
			grep -qx '$(ORB_MACHINE)' && \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -c \
			"rm -rf $(BUILDROOT_OUTPUT_DIR)" || true
else
	@rm -rf $(BUILDROOT_OUTPUT_DIR)
endif

clean-vm:
ifeq ($(OS),Darwin)
	@command -v orb >/dev/null 2>&1 && \
		orb list --quiet 2>/dev/null | \
			grep -qx '$(ORB_MACHINE)' && \
		orb delete '$(ORB_MACHINE)' || true
else
	@echo "clean-vm is only applicable on macOS (Darwin)." >&2
endif

Makefile: ;

%: $(BUILDROOT_STAMP) prepare_vm FORCE
	@mkdir -p $(LOG_DIR); \
	LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; \
	echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || \
	      "$@" == *xconfig || "$@" == *gconfig ]]; then \
		$(call RUN_CMD,$@); \
	else \
		$(call RUN_CMD,$@) 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
