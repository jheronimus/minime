# Shared Makefile targets for Alpine and Buildroot packaging.
# Expects MINIME_ROOT, TARGET_NAME, BOARD, UI, PODMAN_CMD, PODMAN_TTY, PACKAGER_PLATFORM, PACKAGER_IMAGE to be defined.

PACKAGER_IMAGE ?= $(BUILDER_IMAGE)
PACKAGER_USER ?= --user 0:0
# --platform is host-arch-conditional: pass it only when the image arch
# differs from the host (see each target Makefile's PLATFORM_ARGS).
PLATFORM_ARGS ?= --platform $(PACKAGER_PLATFORM)

.PHONY: image update clean

image:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	$(PODMAN_CMD) run $(PODMAN_TTY) --rm $(PACKAGER_USER) $(PLATFORM_ARGS) \
		-v $(MINIME_ROOT):/workspace \
		$(PACKAGER_IMAGE) \
		sh -c "/workspace/minime/build/genassets.sh $(UI) /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)/ui $(TARGET_NAME) && /workspace/minime/build/mkimage.sh --target $(TARGET_NAME) --board $(BOARD) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --ui $(UI) && /workspace/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)"

update:
	@mkdir -p $(CURDIR)/out/$(BOARD)
	$(PODMAN_CMD) run $(PODMAN_TTY) --rm $(PACKAGER_USER) $(PLATFORM_ARGS) \
		-v $(MINIME_ROOT):/workspace \
		$(PACKAGER_IMAGE) \
		sh -c "/workspace/minime/build/mkupdate.sh --target $(TARGET_NAME) --board $(BOARD) --ui $(UI) --input-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD) --output-dir /workspace/minime/targets/$(TARGET_NAME)/out/$(BOARD)"

clean:
	@rm -rf $(CURDIR)/out/$(BOARD)
