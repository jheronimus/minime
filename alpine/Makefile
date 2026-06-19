SHELL := /bin/bash
ROOT_DIR := $(CURDIR)
OS := $(shell uname -s)

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
    CONTAINER_PLATFORM := linux/amd64
else ifeq ($(UNAME_M),arm64)
    CONTAINER_PLATFORM := linux/arm64
else ifeq ($(UNAME_M),aarch64)
    CONTAINER_PLATFORM := linux/arm64
endif
PLATFORM_ARG := $(if $(CONTAINER_PLATFORM),--platform $(CONTAINER_PLATFORM),)

USE_PODMAN ?= 1

PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
IS_PODMAN := $(shell [ "$$(basename $(PODMAN_CMD))" = "podman" ] && echo 1 || echo 0)

PODMAN_IMAGE := minime-builder
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

ifeq ($(IS_PODMAN),1)
    # Rootless Podman uses keep-id and host directory mapping to handle user namespace permissions cleanly on Alpine
    PODMAN_RUN_ARGS := $(PODMAN_TTY) --rm --userns=keep-id --user $(HOST_UID):$(HOST_GID) $(PLATFORM_ARG) \
        -e HOME=/buildroot-output \
        -e CCACHE_DIR=/buildroot-output/ccache \
        -e BR2_CCACHE_DIR=/buildroot-output/ccache \
        -v $(ROOT_DIR):/workspace \
        -v $(HOME)/buildroot-output:/buildroot-output \
        -v $(HOME)/.buildroot-ccache:/buildroot-output/ccache \
        -v $(HOME)/.buildroot-dl:/buildroot-output/dl
else
    # Standard Docker configuration fallback
    PODMAN_RUN_ARGS := $(PODMAN_TTY) --rm --user $(HOST_UID):$(HOST_GID) $(PLATFORM_ARG) \
        -e HOME=/buildroot-output \
        -e CCACHE_DIR=/buildroot-output/ccache \
        -e BR2_CCACHE_DIR=/buildroot-output/ccache \
        -v $(ROOT_DIR):/workspace \
        -v minime-buildroot-output:/buildroot-output \
        -v minime-buildroot-ccache:/buildroot-output/ccache \
        -v minime-buildroot-dl:/buildroot-output/dl
endif

BUILDROOT_VERSION := 2026.05
BUILDROOT_ARCHIVE := buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_URL := https://buildroot.org/downloads/$(BUILDROOT_ARCHIVE)
BUILDROOT_DIR := buildroot
BUILDROOT_STAMP := $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp
SUPPORTED_BOARDS := h700 rk3326 rk3566
BOARD ?= rk3566

# Alpine image variant.  The Alpine build MUST run in a container
# (abuild is Alpine-specific, the cross-toolchain is built from
# Alpine's aarch64 sub-architecture repos).  Force USE_PODMAN=1 for
# the alpine-* targets regardless of the host-level setting so a
# caller that builds Buildroot natively (USE_PODMAN=0) does not
# silently run the Alpine build outside a container.
ifeq ($(MAKECMDGOALS),)
ALPINE_FORCE_PODMAN := 0
else ifneq ($(filter alpine-%,$(MAKECMDGOALS)),)
ALPINE_FORCE_PODMAN := 1
else
ALPINE_FORCE_PODMAN := 0
endif
ifeq ($(ALPINE_FORCE_PODMAN),1)
override USE_PODMAN := 1
endif

ALPINE_IMAGE_NAME := minime-builder-alpine
ALPINE_DIR := $(ROOT_DIR)/alpine
# All Alpine paths use $(HOME)/... so they are the host paths regardless
# of USE_PODMAN.  The bind mount's source side must be a real host path;
# using BASE_OUTPUT_DIR (which is /buildroot-output under USE_PODMAN=1)
# would try to mkdir a non-existent path on the host.
ALPINE_OUTPUT_DIR := $(HOME)/buildroot-output/alpine-$(BOARD)
ALPINE_PACKAGES_DIR := $(ALPINE_OUTPUT_DIR)/packages
ALPINE_STAGE_DIR := $(ALPINE_OUTPUT_DIR)/stage
ALPINE_REPOS_DIR := $(HOME)/alpine-repos
ALPINE_CCACHE_DIR := $(HOME)/alpine-ccache
ALPINE_DL_DIR := $(HOME)/alpine-dl
ALPINE_VERSION := v3.24
ALPINE_ARCH := aarch64
ALPINE_JOBS ?= $(TOPLEVEL_JLEVEL)

ifeq ($(filter $(BOARD),$(SUPPORTED_BOARDS)),)
    $(error Invalid BOARD="$(BOARD)". Supported boards: $(SUPPORTED_BOARDS))
endif

ifeq ($(USE_PODMAN),1)
    LINUX_ROOT := /workspace
    BASE_OUTPUT_DIR := /buildroot-output
    BUILDROOT_CCACHE_DIR := /buildroot-output/ccache
    BUILDROOT_DL_DIR := /buildroot-output/dl
else
    LINUX_ROOT := $(ROOT_DIR)
    BASE_OUTPUT_DIR := $(HOME)/buildroot-output
    BUILDROOT_CCACHE_DIR := $(HOME)/.buildroot-ccache
    BUILDROOT_DL_DIR := $(HOME)/.buildroot-dl
endif

BUILDROOT_OUTPUT_DIR := $(BASE_OUTPUT_DIR)/$(BOARD)
BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := minime_$(BOARD)_defconfig

TOPLEVEL_JLEVEL ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
LOG_DIR := $(CURDIR)/logs
# ALPINE_BUILD_LOG must be assigned AFTER LOG_DIR is defined; the
# Alpine config block at the top of the Makefile references it.
ALPINE_BUILD_LOG := $(LOG_DIR)/alpine-image-$(BOARD).log

BUILDROOT_MAKE_ARGS := BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(BUILDROOT_OUTPUT_DIR) BR2_CCACHE_DIR=$(BUILDROOT_CCACHE_DIR) BR2_DL_DIR=$(BUILDROOT_DL_DIR)

# ALPINE_RUN_ARGS: defined here (after BUILDROOT_OUTPUT_DIR) so the
# bind mounts resolve correctly.  The Alpine build reuses Buildroot's
# bootloader artifacts; the /buildroot-output mount gives the container
# read access to $(HOME)/buildroot-output/<board>/images/ (idbloader.img,
# u-boot.itb, etc.) without coupling to a specific board name.
ifeq ($(IS_PODMAN),1)
    ALPINE_RUN_ARGS := $(PODMAN_TTY) --rm --userns=keep-id --user $(HOST_UID):$(HOST_GID) $(PLATFORM_ARG) \
        -e HOME=/alpine-output \
        -v $(ROOT_DIR):/workspace \
        -v $(ALPINE_OUTPUT_DIR):/alpine-output \
        -v $(ALPINE_REPOS_DIR):/alpine-repos \
        -v $(ALPINE_CCACHE_DIR):/alpine-ccache \
        -v $(ALPINE_DL_DIR):/alpine-dl \
        -v $(HOME)/buildroot-output:/buildroot-output
else
    ALPINE_RUN_ARGS := $(PODMAN_TTY) --rm --user $(HOST_UID):$(HOST_GID) $(PLATFORM_ARG) \
        -e HOME=/alpine-output \
        -v $(ROOT_DIR):/workspace \
        -v $(ALPINE_OUTPUT_DIR):/alpine-output \
        -v $(ALPINE_REPOS_DIR):/alpine-repos \
        -v $(ALPINE_CCACHE_DIR):/alpine-ccache \
        -v $(ALPINE_DL_DIR):/alpine-dl \
        -v $(HOME)/buildroot-output:/buildroot-output
endif

ifeq ($(USE_PODMAN),1)
    RUN_CMD = $(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) make -C /workspace/$(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)
else
    RUN_CMD = $(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) $(1)
endif

export LINUX_ROOT BUILDROOT_DIR BASE_OUTPUT_DIR BUILDROOT_OUTPUT_DIR BUILDROOT_MAKE_ARGS BOARD USE_PODMAN PODMAN_CMD

.PHONY: help prepare shell buildroot defconfig image h700-uboot clean clean-all clean-vm copy_images prepare_vm check-package packages-list FORCE

help:
	@printf '%s\n' \
		"Minime Firmware Build Orchestrator" \
		"==================================" \
		"Commands:" \
		"  make defconfig     - Merge config fragments for BOARD (default: rk3566)" \
		"  make image         - Build complete bootable firmware image for BOARD" \
		"  make alpine-image  - Build Alpine-based immutable rootfs image for BOARD" \
		"  make alpine-shell  - Open an interactive shell inside the Alpine build container" \
		"  make alpine-prepare - Build the Alpine builder container image" \
		"  make shell         - Open an interactive shell inside the build container" \
		"  make prepare       - Build builder container image (or install host tools on Linux)" \
		"  make h700-uboot    - Compile and update prebuilt H700 bootloader" \
		"  make check-rebuild - Scan packages for out-of-date build stamps" \
		"  make check-package CHECK_PACKAGE_FILES='path ...'" \
		"                       Run Buildroot's package linter on specified files" \
		"  make packages-list - Regenerate package inventory documentation (docs/PACKAGES.md)" \
		"  make clean         - Remove compilation output for active BOARD" \
		"  make clean-all     - Remove ALL compilation outputs and delete Buildroot source tree" \
		"  make clean-vm      - Delete container images and clean up volumes" \
		"  make <target>      - Pass arbitrary command directly to Buildroot (e.g., make menuconfig)" \
		"" \
		"Options (override with VAR=value):" \
		"  BOARD              - Target hardware (default: rk3566, supported: $(SUPPORTED_BOARDS))" \
		"  USE_PODMAN         - Toggle build container isolation (default: 1, set to 0 for host build)" \
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

prepare_vm:
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) info >/dev/null 2>&1 || (echo "ERROR: $(PODMAN_CMD) daemon is not running or not accessible." >&2 && exit 1)
	@if [ "$(IS_PODMAN)" = "1" ]; then mkdir -p $(HOME)/buildroot-output $(HOME)/.buildroot-ccache $(HOME)/.buildroot-dl; fi
	@$(PODMAN_CMD) image inspect $(PODMAN_IMAGE) >/dev/null 2>&1 || $(MAKE) prepare
endif

prepare:
ifeq ($(USE_PODMAN),1)
	@echo "Building container image '$(PODMAN_IMAGE)'..."
	@$(PODMAN_CMD) build $(PLATFORM_ARG) -t $(PODMAN_IMAGE) -f container/Dockerfile .
else
	@./scripts/prepare-linux.sh
endif

shell: prepare_vm
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run -it $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) /bin/bash
else
	@bash
endif

defconfig: $(BUILDROOT_STAMP) prepare_vm
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	set -o pipefail; \
	if [ "$(USE_PODMAN)" = "1" ]; then \
		$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) sh -c "\
			mkdir -p $(BUILDROOT_OUTPUT_DIR) && \
			/workspace/$(BUILDROOT_DIR)/support/kconfig/merge_config.sh \
				-O $(BUILDROOT_OUTPUT_DIR) \
				-m \
				/workspace/external/configs/minime_common.config \
				/workspace/external/configs/minime_$(BOARD).config && \
			make -C /workspace/$(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) olddefconfig" 2>&1 | tee "$$LOG_FILE"; \
	else \
		mkdir -p $(BUILDROOT_OUTPUT_DIR) && \
		$(BUILDROOT_DIR)/support/kconfig/merge_config.sh \
			-O $(BUILDROOT_OUTPUT_DIR) \
			-m \
			external/configs/minime_common.config \
			external/configs/minime_$(BOARD).config 2>&1 | tee "$$LOG_FILE" && \
		$(MAKE) -C $(BUILDROOT_DIR) $(BUILDROOT_MAKE_ARGS) olddefconfig 2>&1 | tee -a "$$LOG_FILE"; \
	fi

image: $(BUILDROOT_STAMP) prepare_vm defconfig
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	set -o pipefail; $(call RUN_CMD,-j$(TOPLEVEL_JLEVEL)) 2>&1 | tee "$$LOG_FILE"
	@$(MAKE) copy_images

.PHONY: alpine-image alpine-prepare alpine-shell

alpine-prepare:
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) info >/dev/null 2>&1 || (echo "ERROR: $(PODMAN_CMD) daemon is not running or not accessible." >&2 && exit 1)
	@mkdir -p $(ALPINE_OUTPUT_DIR) $(ALPINE_REPOS_DIR) $(ALPINE_CCACHE_DIR) $(ALPINE_DL_DIR)
	@$(PODMAN_CMD) image inspect $(ALPINE_IMAGE_NAME) >/dev/null 2>&1 || \
		$(PODMAN_CMD) build $(PLATFORM_ARG) -t $(ALPINE_IMAGE_NAME) -f alpine/container/Dockerfile .
else
	@./scripts/prepare-linux.sh
endif

alpine-shell: alpine-prepare
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run -it $(ALPINE_RUN_ARGS) $(ALPINE_IMAGE_NAME) /bin/sh
else
	@cd $(ALPINE_DIR) && ./scripts/build.sh shell
endif

alpine-image: alpine-prepare
	@if [ ! -d "$(HOME)/buildroot-output/$(BOARD)/images" ] || [ -z "$$(ls $(HOME)/buildroot-output/$(BOARD)/images/u-boot*.itb 2>/dev/null; ls $(HOME)/buildroot-output/$(BOARD)/images/idbloader.img 2>/dev/null; ls $(HOME)/buildroot-output/$(BOARD)/images/u-boot-sunxi-with-spl.bin 2>/dev/null)" ]; then \
		echo "ERROR: Alpine build reuses Buildroot bootloader artifacts." >&2; \
		echo "ERROR: Run 'make image BOARD=$(BOARD)' first or 'make h700-uboot BOARD=$(BOARD)' for h700." >&2; \
		exit 1; \
	fi
	@mkdir -p $(LOG_DIR); LOG_FILE="$(ALPINE_BUILD_LOG)"; echo "LOG=$$LOG_FILE"; \
	$(PODMAN_CMD) run $(ALPINE_RUN_ARGS) $(ALPINE_IMAGE_NAME) \
		sh -c "BOARD=$(BOARD) ALPINE_JOBS=$(ALPINE_JOBS) ALPINE_DIR=/workspace/alpine LINUX_ROOT=/workspace BUILDROOT_OUTPUT_DIR=/buildroot-output/$(BOARD) /workspace/alpine/scripts/build.sh all" \
		2>&1 | tee "$$LOG_FILE"
	@mkdir -p $(CURDIR)/out/alpine/$(BOARD)
	@if [ -d $(HOME)/buildroot-output/alpine-$(BOARD)/images ]; then \
		cp -f $(HOME)/buildroot-output/alpine-$(BOARD)/images/minime-alpine-$(BOARD).img.gz $(CURDIR)/out/alpine/$(BOARD)/ 2>/dev/null || true; \
	fi

copy_images:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	@echo "Copying built firmware images to out/$(BOARD)/..."
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) sh -c "mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(LINUX_ROOT)/out/$(BOARD)/ 2>/dev/null || true"
else
	@mkdir -p $(BUILDROOT_OUTPUT_DIR)/images
	@cp -r $(BUILDROOT_OUTPUT_DIR)/images/* out/$(BOARD)/ 2>/dev/null || true
endif

check-package: prepare_vm
	@if [ -z "$(CHECK_PACKAGE_FILES)" ]; then \
		echo "ERROR: set CHECK_PACKAGE_FILES='path ...'" >&2; \
		exit 1; \
	fi
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) python3 /workspace/buildroot/utils/check-package $(CHECK_PACKAGE_FILES)
else
	@python3 buildroot/utils/check-package $(CHECK_PACKAGE_FILES)
endif


packages-list:
	python3 scripts/generate_packages_doc.py

clean:
	@rm -rf $(LOG_DIR) out/$(BOARD)/
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) rm -rf $(BUILDROOT_OUTPUT_DIR) 2>/dev/null || true
else
	@rm -rf $(BUILDROOT_OUTPUT_DIR)
endif

clean-all:
	@rm -rf $(BUILDROOT_DIR) $(LOG_DIR) $(CURDIR)/out/
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) rm -rf $(BASE_OUTPUT_DIR) 2>/dev/null || true
else
	@rm -rf $(BASE_OUTPUT_DIR)
endif

clean-vm:
ifeq ($(USE_PODMAN),1)
	@echo "Deleting container images..."
	@if [ "$(IS_PODMAN)" = "0" ]; then $(PODMAN_CMD) volume rm minime-buildroot-output minime-buildroot-ccache minime-buildroot-dl 2>/dev/null || true; fi
	@$(PODMAN_CMD) rmi $(PODMAN_IMAGE) 2>/dev/null || true
else
	@echo "clean-vm is only applicable when using Podman." >&2
endif

h700-uboot: $(BUILDROOT_STAMP) prepare_vm
	@if [ "$(BOARD)" != "h700" ]; then \
		echo "ERROR: h700-uboot only supports BOARD=h700" >&2; \
		exit 1; \
	fi
	@echo "Configuring source U-Boot build for h700..."
	@$(MAKE) defconfig BOARD=h700
	@if [ "$(USE_PODMAN)" = "1" ]; then \
		$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) sh -c "\
			grep -v -E '^(# BR2_TARGET_ARM_TRUSTED_FIRMWARE is not set|# BR2_TARGET_UBOOT is not set)' /buildroot-output/h700/.config > /buildroot-output/h700/.config.tmp && \
			mv /buildroot-output/h700/.config.tmp /buildroot-output/h700/.config && \
			printf '%s\n' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE=y' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION=y' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION_VALUE=\"v2.15.0\"' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_PLATFORM=\"sun50i_h616\"' \
			'BR2_TARGET_UBOOT=y' \
			'BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG=y' \
			'BR2_TARGET_UBOOT_CUSTOM_VERSION=y' \
			'BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE=\"2026.04\"' \
			'BR2_TARGET_UBOOT_BOARD_DEFCONFIG=\"anbernic_rg35xx_h700\"' \
			'BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES=\"/workspace/external/board/h700/uboot.config\"' \
			'BR2_TARGET_UBOOT_NEEDS_DTC=y' \
			'BR2_TARGET_UBOOT_NEEDS_PYLIBFDT=y' \
			'BR2_TARGET_UBOOT_NEEDS_OPENSSL=y' \
			'BR2_TARGET_UBOOT_NEEDS_ATF_BL31=y' \
			'BR2_TARGET_UBOOT_SPL=y' \
			'BR2_TARGET_UBOOT_SPL_NAME=\"u-boot-sunxi-with-spl.bin\"' \
			>> /buildroot-output/h700/.config"; \
	else \
		grep -v -E '^(# BR2_TARGET_ARM_TRUSTED_FIRMWARE is not set|# BR2_TARGET_UBOOT is not set)' $(BUILDROOT_OUTPUT_DIR)/.config > $(BUILDROOT_OUTPUT_DIR)/.config.tmp; \
		mv $(BUILDROOT_OUTPUT_DIR)/.config.tmp $(BUILDROOT_OUTPUT_DIR)/.config; \
		printf '%s\n' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE=y' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION=y' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_CUSTOM_VERSION_VALUE="v2.15.0"' \
			'BR2_TARGET_ARM_TRUSTED_FIRMWARE_PLATFORM="sun50i_h616"' \
			'BR2_TARGET_UBOOT=y' \
			'BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG=y' \
			'BR2_TARGET_UBOOT_CUSTOM_VERSION=y' \
			'BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="2026.04"' \
			'BR2_TARGET_UBOOT_BOARD_DEFCONFIG="anbernic_rg35xx_h700"' \
			'BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL)/board/h700/uboot.config"' \
			'BR2_TARGET_UBOOT_NEEDS_DTC=y' \
			'BR2_TARGET_UBOOT_NEEDS_PYLIBFDT=y' \
			'BR2_TARGET_UBOOT_NEEDS_OPENSSL=y' \
			'BR2_TARGET_UBOOT_NEEDS_ATF_BL31=y' \
			'BR2_TARGET_UBOOT_SPL=y' \
			'BR2_TARGET_UBOOT_SPL_NAME="u-boot-sunxi-with-spl.bin"' \
			>> $(BUILDROOT_OUTPUT_DIR)/.config; \
	fi
	@$(call RUN_CMD,olddefconfig)
	@echo "Building H700 U-Boot from source..."
	@$(call RUN_CMD,-j$(TOPLEVEL_JLEVEL) arm-trusted-firmware uboot)
	@echo "Copying H700 U-Boot prebuilt into external/board/h700/prebuilt/..."
ifeq ($(USE_PODMAN),1)
	@$(PODMAN_CMD) run $(PODMAN_RUN_ARGS) $(PODMAN_IMAGE) sh -c "mkdir -p /workspace/external/board/h700/prebuilt && cp -f /buildroot-output/h700/images/u-boot-sunxi-with-spl.bin /workspace/external/board/h700/prebuilt/u-boot-sunxi-with-spl.bin"
else
	@mkdir -p external/board/h700/prebuilt
	@cp -f $(BUILDROOT_OUTPUT_DIR)/images/u-boot-sunxi-with-spl.bin external/board/h700/prebuilt/u-boot-sunxi-with-spl.bin
endif

Makefile: ;


%: $(BUILDROOT_STAMP) prepare_vm FORCE
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || "$@" == *xconfig || "$@" == *gconfig ]]; then \
		$(call RUN_CMD,$@); \
	else \
		set -o pipefail; $(call RUN_CMD,$@) 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
