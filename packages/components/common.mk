# Shared Makefile targets for Alpine and Buildroot packaging.
# Expects MINIME_ROOT, TARGET_NAME, BOARD, UI, PODMAN_CMD, PODMAN_TTY, PACKAGER_PLATFORM, PACKAGER_IMAGE to be defined.

PACKAGER_IMAGE ?= $(BUILDER_IMAGE)
PACKAGER_USER ?= --user 0:0
PLATFORM_ARGS ?= --platform $(PACKAGER_PLATFORM)

INCLUDE_ROMS ?= $(if $(ROMS),$(ROMS),0)
ROMS_FLAG := $(if $(filter 1 true yes,$(INCLUDE_ROMS)),--include-roms,)

IN_CONTAINER := $(if $(MINIME_IN_CONTAINER),yes)

OUT_DIR := $(CURDIR)/out/$(BOARD)

.PHONY: image update clean

image update:
	@mkdir -p $(OUT_DIR)
	@if [ "$(IN_CONTAINER)" = "yes" ]; then \
		$(MINIME_ROOT)/packages/image/build.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) $(ROMS_FLAG) --input-dir $(OUT_DIR) --output-dir $(OUT_DIR); \
	else \
		$(PODMAN_CMD) run $(PODMAN_TTY) --rm $(PACKAGER_USER) $(PLATFORM_ARGS) \
			-e MINIME_COMMIT -e UI_COMMIT -e INCLUDE_ROMS \
			-v $(MINIME_ROOT):/workspace \
			$(PACKAGER_IMAGE) \
			sh -c "/workspace/packages/image/build.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) $(ROMS_FLAG) --input-dir /workspace/packages/components/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/packages/components/$(TARGET_NAME)/out/$(BOARD)"; \
	fi

clean:
	@rm -rf $(OUT_DIR)
