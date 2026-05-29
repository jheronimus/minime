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
BUILDROOT_STAMP := $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp

ifeq ($(OS),Darwin)
    LINUX_ROOT := /mnt/mac$(ROOT_DIR)
    BUILDROOT_OUTPUT_DIR := /home/$(ORB_USER)/buildroot-output
else
    LINUX_ROOT := $(ROOT_DIR)
    BUILDROOT_OUTPUT_DIR := $(HOME)/buildroot-output
endif

BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := minime_defconfig
TOPLEVEL_JLEVEL ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
LOG_DIR := $(CURDIR)/logs
BUILDROOT_MAKE_ARGS := BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(BUILDROOT_OUTPUT_DIR)

export ORB_MACHINE
export ORB_USER
export LINUX_ROOT
export BUILDROOT_DIR
export BUILDROOT_OUTPUT_DIR
export BUILDROOT_MAKE_ARGS

.PHONY: help prepare vm shell buildroot defconfig image clean clean-vm FORCE

help:
	@printf '%s\n' \
		"minime firmware build orchestrator:" \
		"  make prepare            - Provision host (Linux) or OrbStack VM (macOS)" \
		"  make vm                 - Setup and provision OrbStack Debian VM (alias for prepare)" \
		"  make shell              - Open a terminal shell (in VM on macOS, natively on Linux)" \
		"  make buildroot          - Download/extract Buildroot $(BUILDROOT_VERSION) (on-demand)" \
		"  make defconfig          - Apply $(MINIME_DEFCONFIG)" \
		"  make image              - Compile and build complete bootable firmware image" \
		"  make clean              - Remove local out/ and buildroot directories" \
		"  make clean-vm           - Delete OrbStack VM '$(ORB_MACHINE)' (macOS)" \
		"  make <target>           - Pass target directly to Buildroot"

$(BUILDROOT_STAMP):
	@mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/buildroot-fetch-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; set -o pipefail; { \
		set -e; \
		echo "Downloading Buildroot $(BUILDROOT_VERSION)..."; \
		if command -v wget >/dev/null 2>&1; then \
			wget -q --show-progress "$(BUILDROOT_URL)"; \
		else \
			curl -fL -o "$(BUILDROOT_ARCHIVE)" "$(BUILDROOT_URL)"; \
		fi; \
		rm -rf $(BUILDROOT_DIR); \
		mkdir -p $(BUILDROOT_DIR); \
		tar xf $(BUILDROOT_ARCHIVE) --strip-components=1 -C $(BUILDROOT_DIR); \
		touch $(BUILDROOT_STAMP); \
		rm -f $(BUILDROOT_ARCHIVE); \
	} 2>&1 | tee "$$LOG_FILE"

buildroot: $(BUILDROOT_STAMP)
	@echo "Buildroot $(BUILDROOT_VERSION) is ready in $(BUILDROOT_DIR)"

prepare:
	@./scripts/prepare.sh

vm: prepare

shell:
	@set -eu; \
	if [ "$(OS)" = "Darwin" ]; then \
		if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
			make prepare; \
		fi; \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)' sh; \
	else \
		bash; \
	fi

defconfig: $(BUILDROOT_STAMP)
	@set -eu -o pipefail; \
	if [ "$(OS)" = "Darwin" ] && ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make prepare; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	./scripts/run.sh "make $(BUILDROOT_MAKE_ARGS) $(MINIME_DEFCONFIG)" 2>&1 | tee "$$LOG_FILE"

image: $(BUILDROOT_STAMP)
	@set -eu -o pipefail; \
	if [ "$(OS)" = "Darwin" ] && ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make prepare; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	./scripts/run.sh "make $(BUILDROOT_MAKE_ARGS) -j$(TOPLEVEL_JLEVEL)" 2>&1 | tee "$$LOG_FILE"; \
	mkdir -p $(CURDIR)/out; \
	echo "Copying built firmware images to out/..."; \
	if [ "$(OS)" = "Darwin" ]; then \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -lc "mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(LINUX_ROOT)/out/ 2>/dev/null || true"; \
	else \
		mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(ROOT_DIR)/out/ 2>/dev/null || true; \
	fi

clean:
	rm -rf $(BUILDROOT_DIR) $(LOG_DIR) out/
	@if [ "$(OS)" = "Darwin" ]; then \
		if command -v orb >/dev/null 2>&1 && orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
			echo "Cleaning VM native output directory..."; \
			orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -c 'rm -rf $(BUILDROOT_OUTPUT_DIR)'; \
		fi; \
	else \
		echo "Cleaning local buildroot output directory..."; \
		rm -rf $(BUILDROOT_OUTPUT_DIR); \
	fi

clean-vm:
	@set -eu; \
	if [ "$(OS)" = "Darwin" ]; then \
		command -v orb >/dev/null 2>&1 || { \
			printf '%s\n' "ERROR: OrbStack CLI 'orb' not found" >&2; \
			exit 1; \
		}; \
		if orb list --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
			orb delete '$(ORB_MACHINE)'; \
		fi; \
	else \
		echo "clean-vm is only applicable on macOS (Darwin)." >&2; \
	fi

Makefile: ;

%: $(BUILDROOT_STAMP) FORCE
	@set -eu -o pipefail; \
	if [ "$(OS)" = "Darwin" ] && ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make prepare; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || "$@" == *xconfig || "$@" == *gconfig ]]; then \
		./scripts/run.sh "make $(BUILDROOT_MAKE_ARGS) $@"; \
	else \
		./scripts/run.sh "make $(BUILDROOT_MAKE_ARGS) $@" 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
