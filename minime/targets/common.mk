# Shared Makefile targets for Alpine and Buildroot packaging.
# Expects MINIME_ROOT, TARGET_NAME, BOARD, UI, PODMAN_CMD, PODMAN_TTY, PACKAGER_PLATFORM, PACKAGER_IMAGE to be defined.

PACKAGER_IMAGE ?= $(BUILDER_IMAGE)
PACKAGER_USER ?= --user 0:0
# --platform is host-arch-conditional: pass it only when the image arch
# differs from the host (see each target Makefile's PLATFORM_ARGS).
PLATFORM_ARGS ?= --platform $(PACKAGER_PLATFORM)

# CI runs inside the builder container (GitHub container job), so packaging
# runs directly against the workspace. Local dev wraps in podman.
IN_CONTAINER := $(if $(MINIME_IN_CONTAINER),yes)

OUT_DIR := $(CURDIR)/out/$(BOARD)

.PHONY: image update clean

image:
	@mkdir -p $(OUT_DIR)
	@if [ "$(IN_CONTAINER)" = "yes" ]; then \
		$(MINIME_ROOT)/minime/build/genassets.sh $(UI) $(OUT_DIR)/ui-$(UI) $(TARGET_NAME) && \
		$(MINIME_ROOT)/minime/build/mkimage.sh --target $(TARGET_NAME) --board $(BOARD) --input-dir $(OUT_DIR) --output-dir $(OUT_DIR) --ui $(UI) && \
		$(MINIME_ROOT)/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir $(OUT_DIR) --output-dir $(OUT_DIR); \
	else \
		$(PODMAN_CMD) run $(PODMAN_TTY) --rm $(PACKAGER_USER) $(PLATFORM_ARGS) \
			-e MINIME_COMMIT -e UI_COMMIT \
			-v $(MINIME_ROOT):/workspace \
			$(PACKAGER_IMAGE) \
			sh -c "/workspace/minime/build/genassets.sh $(UI) /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)/ui-$(UI) $(TARGET_NAME) && /workspace/minime/build/mkimage.sh --target $(TARGET_NAME) --board $(BOARD) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --ui $(UI) && /workspace/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)"; \
	fi

update:
	@mkdir -p $(OUT_DIR)
	@if [ "$(IN_CONTAINER)" = "yes" ]; then \
		$(MINIME_ROOT)/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir $(OUT_DIR) --output-dir $(OUT_DIR); \
	else \
		$(PODMAN_CMD) run $(PODMAN_TTY) --rm $(PACKAGER_USER) $(PLATFORM_ARGS) \
			-e MINIME_COMMIT -e UI_COMMIT \
			-v $(MINIME_ROOT):/workspace \
			$(PACKAGER_IMAGE) \
			sh -c "/workspace/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)"; \
	fi

clean:
	@rm -rf $(OUT_DIR)
