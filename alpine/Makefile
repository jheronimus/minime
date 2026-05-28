SHELL := /bin/bash

ROOT_DIR := $(CURDIR)
LINUX_ROOT := /mnt/mac$(ROOT_DIR)

ORB_MACHINE ?= builder
ORB_DISTRO ?= debian
ORB_ARCH ?= arm64
ORB_USER ?= $(shell id -un 2>/dev/null || printf '%s\n' builder)

BUILDROOT_VERSION := 2026.02.2
BUILDROOT_ARCHIVE := buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_URL := https://buildroot.org/downloads/$(BUILDROOT_ARCHIVE)
BUILDROOT_DIR := buildroot
BUILDROOT_STAMP := $(BUILDROOT_DIR)/.minime-buildroot-$(BUILDROOT_VERSION).stamp

BR2_EXTERNAL := $(LINUX_ROOT)/external
MINIME_DEFCONFIG := minime_defconfig
TOPLEVEL_JLEVEL ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
LOG_DIR := $(CURDIR)/logs
BUILDROOT_OUTPUT_DIR := /home/$(ORB_USER)/buildroot-output
BUILDROOT_MAKE_ARGS := BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(BUILDROOT_OUTPUT_DIR)

BOOTSTRAP_PACKAGES := \
	build-essential \
	bison \
	flex \
	gettext \
	texinfo \
	unzip \
	help2man \
	rsync \
	git \
	curl \
	ccache \
	cmake \
	mold \
	ninja-build \
	libelf-dev \
	libssl-dev \
	bc \
	python3 \
	python3-dev \
	swig \
	u-boot-tools \
	cpio \
	genimage \
	mtools \
	dosfstools \
	parted \
	erofs-utils \
	patchelf \
	file \
	wget

.PHONY: help vm shell buildroot defconfig image clean clean-vm FORCE

help:
	@printf '%s\n' \
		"minime firmware build orchestrator:" \
		"  make vm                 - Setup and provision OrbStack Debian Bookworm VM ('$(ORB_MACHINE)')" \
		"  make shell              - Open a terminal shell in the '$(ORB_MACHINE)' VM" \
		"  make buildroot          - Download/extract Buildroot $(BUILDROOT_VERSION) (on-demand)" \
		"  make defconfig          - Apply $(MINIME_DEFCONFIG) inside VM" \
		"  make image              - Compile and build complete bootable firmware image inside VM" \
		"  make clean              - Remove local out/ and buildroot directories" \
		"  make clean-vm           - Delete OrbStack VM '$(ORB_MACHINE)'" \
		"  make <target>           - Pass target directly to Buildroot inside VM"

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

vm:
	@set -eu; \
	command -v orb >/dev/null 2>&1 || { \
		printf '%s\n' "ERROR: OrbStack CLI 'orb' not found" >&2; \
		exit 1; \
	}; \
	if ! orb list --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		echo "Creating OrbStack VM '$(ORB_MACHINE)' ($(ORB_DISTRO)/$(ORB_ARCH))..."; \
		orb create -a '$(ORB_ARCH)' -u '$(ORB_USER)' '$(ORB_DISTRO)' '$(ORB_MACHINE)'; \
	fi; \
	if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		orb start '$(ORB_MACHINE)' >/dev/null; \
	fi; \
	echo "Installing host-side build packages inside VM..."; \
	orb -m '$(ORB_MACHINE)' -u root sh -lc ' \
		set -eu; \
		apt-get update; \
		apt-get install -y $(BOOTSTRAP_PACKAGES); \
	'; \
	printf '%s\n' "OrbStack VM '$(ORB_MACHINE)' is ready."

shell:
	@set -eu; \
	command -v orb >/dev/null 2>&1 || { \
		printf '%s\n' "ERROR: OrbStack CLI 'orb' not found" >&2; \
		exit 1; \
	}; \
	if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make vm; \
	fi; \
	orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)' sh

defconfig: $(BUILDROOT_STAMP)
	@set -eu -o pipefail; \
	if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make vm; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/defconfig-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)/$(BUILDROOT_DIR)' \
		sh -lc "make $(BUILDROOT_MAKE_ARGS) $(MINIME_DEFCONFIG)" 2>&1 | tee "$$LOG_FILE"

image: $(BUILDROOT_STAMP)
	@set -eu -o pipefail; \
	if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make vm; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/image-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)/$(BUILDROOT_DIR)' \
		sh -lc "make $(BUILDROOT_MAKE_ARGS) -j$(TOPLEVEL_JLEVEL)" 2>&1 | tee "$$LOG_FILE"; \
	mkdir -p $(CURDIR)/out; \
	echo "Copying built firmware images to out/..."; \
	orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -lc "mkdir -p $(BUILDROOT_OUTPUT_DIR)/images && cp -r $(BUILDROOT_OUTPUT_DIR)/images/* $(LINUX_ROOT)/out/ 2>/dev/null || true"

clean:
	rm -rf $(BUILDROOT_DIR) $(LOG_DIR) out/
	@if command -v orb >/dev/null 2>&1 && orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		echo "Cleaning VM native output directory..."; \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' sh -c 'rm -rf $(BUILDROOT_OUTPUT_DIR)'; \
	fi

clean-vm:
	@set -eu; \
	command -v orb >/dev/null 2>&1 || { \
		printf '%s\n' "ERROR: OrbStack CLI 'orb' not found" >&2; \
		exit 1; \
	}; \
	if orb list --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		orb delete '$(ORB_MACHINE)'; \
	fi

Makefile: ;

%: $(BUILDROOT_STAMP) FORCE
	@set -eu -o pipefail; \
	if ! orb list --running --quiet 2>/dev/null | grep -qx '$(ORB_MACHINE)'; then \
		make vm; \
	fi; \
	mkdir -p $(LOG_DIR); LOG_FILE="$(LOG_DIR)/$@-$$(date +%F-%H%M%S).log"; echo "LOG=$$LOG_FILE"; \
	if [[ "$@" == *menuconfig || "$@" == *nconfig || "$@" == *xconfig || "$@" == *gconfig ]]; then \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)/$(BUILDROOT_DIR)' \
			sh -c "make $(BUILDROOT_MAKE_ARGS) $@"; \
	else \
		orb -m '$(ORB_MACHINE)' -u '$(ORB_USER)' -w '$(LINUX_ROOT)/$(BUILDROOT_DIR)' \
			sh -lc "make $(BUILDROOT_MAKE_ARGS) $@" 2>&1 | tee "$$LOG_FILE"; \
	fi

FORCE: ;
