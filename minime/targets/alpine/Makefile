MINIME_ROOT := $(abspath $(CURDIR)/../../..)
PODMAN_CMD ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null || echo podman)
PODMAN_TTY := $(shell [ -t 0 ] && echo "-it" || echo "-i")

SUPPORTED_BOARDS := rk3566 h700
BOARD ?= rk3566
UI ?= minui

HOST_ARCH := $(shell uname -m)
PACKAGER_PLATFORM := linux/arm64

BUILDER_IMAGE := ghcr.io/jheronimus/minime-builder-alpine:latest
PACKAGER_IMAGE := ghcr.io/jheronimus/minime-packager:latest

RUN_ARGS := $(PODMAN_TTY) --rm --privileged --user 0:0 --platform linux/arm64 \
	--ulimit nofile=65536:65536 \
	-e HOME=/home/builder \
	-v $(MINIME_ROOT):/workspace \
	-v $(HOME)/alpine-output/$(BOARD):/alpine-output \
	-v $(HOME)/alpine-repos:/alpine-repos \
	-v $(HOME)/alpine-ccache:/alpine-ccache \
	-v $(HOME)/alpine-dl:/alpine-dl

.PHONY: help components image update clean

help:
	@printf '%s\n' \
		"Minime Alpine targets:" \
		"  make components BOARD=rk3566    Build system components (kernel, rootfs, APKs)" \
		"  make image BOARD=rk3566 UI=minui Build full release SD image" \
		"  make update BOARD=rk3566 UI=minui Build update tarball package" \
		"  make clean                      Remove built outputs"

components:
	@mkdir -p $(HOME)/alpine-output/$(BOARD) $(HOME)/alpine-repos $(HOME)/alpine-ccache $(HOME)/alpine-dl $(CURDIR)/out/$(BOARD)
	$(PODMAN_CMD) run $(RUN_ARGS) $(BUILDER_IMAGE) \
		sh -c "BOARD=$(BOARD) UI=$(UI) ALPINE_DIR=/workspace/minime/targets/alpine /workspace/minime/targets/alpine/scripts/build.sh components"
	$(PODMAN_CMD) run $(RUN_ARGS) $(BUILDER_IMAGE) \
		sh -c "BOARD=$(BOARD) UI=$(UI) ALPINE_DIR=/workspace/minime/targets/alpine /workspace/minime/targets/alpine/scripts/build.sh system-image"

image:
	$(PODMAN_CMD) run $(PODMAN_TTY) --rm --platform $(PACKAGER_PLATFORM) \
		-v $(MINIME_ROOT):/workspace \
		$(PACKAGER_IMAGE) \
		sh -c "/workspace/minime/build/genassets.sh $(UI) /workspace/minime/targets/alpine/out/$(BOARD)/ui alpine && /workspace/minime/build/mkimage.sh --target alpine --board $(BOARD) --input-dir /workspace/minime/targets/alpine/out/$(BOARD) --output-dir /workspace/minime/targets/alpine/out/$(BOARD) && /workspace/minime/build/mkupdate.sh --target alpine --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/alpine/out/$(BOARD) --output-dir /workspace/minime/targets/alpine/out/$(BOARD)"

update:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	$(PODMAN_CMD) run $(PODMAN_TTY) --rm --platform $(PACKAGER_PLATFORM) \
		-v $(MINIME_ROOT):/workspace \
		$(PACKAGER_IMAGE) \
		sh -c "/workspace/minime/build/mkupdate.sh --target alpine --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/alpine/out/$(BOARD) --output-dir /workspace/minime/targets/alpine/out/$(BOARD)"

clean:
	@rm -rf $(CURDIR)/out/$(BOARD) $(HOME)/alpine-output/$(BOARD)
