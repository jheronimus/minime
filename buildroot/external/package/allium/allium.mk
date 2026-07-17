################################################################################
#
# allium
#
################################################################################

ALLIUM_VERSION = 3e2d6095817519437a4f7cf691806cc58a02af7c
ALLIUM_SITE = $(call github,jheronimus,Allium,$(ALLIUM_VERSION))
ALLIUM_LICENSE = MIT
ALLIUM_LICENSE_FILES = LICENSE
ALLIUM_DEPENDENCIES = allium-themes dufs host-clang libretro-headers libretro-cores syncthing

ALLIUM_CARGO_ENV = \
	LIBCLANG_PATH=$(HOST_DIR)/lib \
	LIBRETRO_HEADER=$(STAGING_DIR)/usr/include/libretro.h \
	BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(STAGING_DIR) -I$(STAGING_DIR)/usr/include"
ALLIUM_CARGO_BUILD_OPTS = --workspace --features minime
ALLIUM_INSTALL_TARGET = NO
ALLIUM_INSTALL_IMAGES = YES

define ALLIUM_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.ui/bin
	mkdir -p $(BINARIES_DIR)/ui/.ui/config
	mkdir -p $(BINARIES_DIR)/ui/.ui/state
	mkdir -p $(BINARIES_DIR)/ui/apps

	for binary in alliumd allium-launcher allium-menu activity-tracker \
		screenshot screenshot-viewer say show play; do \
		cp -f $(@D)/target/$(RUSTC_TARGET_NAME)/release/$$binary \
			$(BINARIES_DIR)/ui/.ui/bin/; \
	done

	cp -a $(@D)/static/.allium/. $(BINARIES_DIR)/ui/.ui/
	cp -a $(@D)/static/Apps/. $(BINARIES_DIR)/ui/apps/

	# Remove stale absolute symlinks if they exist and replace with wrapper
	# scripts so the files survive mtools copy onto the FAT32 userdata image.
	rm -f "$(BINARIES_DIR)/ui/apps/Activity Tracker.pak/activity-tracker"
	mkdir -p "$(BINARIES_DIR)/ui/apps/Activity Tracker.pak"
	printf '%s\n' \
		'#!/bin/sh' \
		'exec /mnt/sdcard/.ui/bin/activity-tracker "$$@"' \
		> "$(BINARIES_DIR)/ui/apps/Activity Tracker.pak/activity-tracker"
	chmod +x "$(BINARIES_DIR)/ui/apps/Activity Tracker.pak/activity-tracker"

	rm -f "$(BINARIES_DIR)/ui/apps/Screenshot Viewer.pak/screenshot-viewer"
	mkdir -p "$(BINARIES_DIR)/ui/apps/Screenshot Viewer.pak"
	printf '%s\n' \
		'#!/bin/sh' \
		'exec /mnt/sdcard/.ui/bin/screenshot-viewer "$$@"' \
		> "$(BINARIES_DIR)/ui/apps/Screenshot Viewer.pak/screenshot-viewer"
	chmod +x "$(BINARIES_DIR)/ui/apps/Screenshot Viewer.pak/screenshot-viewer"
	$(ALLIUM_PKGDIR)/generate-configs.sh \
		$(BR2_EXTERNAL_MINIME_PATH)/board/common/config/cores.cfg \
		$(BINARIES_DIR)/ui/.ui/config

	printf '%s\n' \
		'#!/bin/sh' \
		'core="$$1"' \
		'rom="$$2"' \
		'exec /mnt/sdcard/.ui/bin/play --core "/mnt/sdcard/.cores/$${core}_libretro.so" --core-id "$$core" --rom "$$rom"' \
		> $(BINARIES_DIR)/ui/.ui/bin/play-launch
	chmod +x $(BINARIES_DIR)/ui/.ui/bin/play-launch

	printf '%s\n' \
		'#!/bin/sh' \
		'core="$$1"' \
		'rom="$$2"' \
		'exec /mnt/sdcard/.ui/bin/play --no-autoload --core "/mnt/sdcard/.cores/$${core}_libretro.so" --core-id "$$core" --rom "$$rom"' \
		> $(BINARIES_DIR)/ui/.ui/bin/launch_without_savestate_auto_load.sh
	chmod +x $(BINARIES_DIR)/ui/.ui/bin/launch_without_savestate_auto_load.sh

	printf '%s\n' \
		'#!/bin/sh' \
		'export ALLIUM_SD_ROOT=/mnt/sdcard' \
		'export ALLIUM_BASE_DIR=/mnt/sdcard/.ui' \
		'export ALLIUM_GAMES_DIR=/mnt/sdcard/roms' \
		'export ALLIUM_APPS_DIR=/mnt/sdcard/apps' \
		'export HOME=/mnt/sdcard' \
		'export PATH=/mnt/sdcard/.ui/bin:/usr/bin:/bin' \
		'exec /mnt/sdcard/.ui/bin/alliumd' \
		> $(BINARIES_DIR)/ui/.ui/launch.sh
	chmod +x $(BINARIES_DIR)/ui/.ui/launch.sh
endef

$(eval $(cargo-package))
