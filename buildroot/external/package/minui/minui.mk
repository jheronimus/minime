################################################################################
#
# minui
#
################################################################################

MINUI_VERSION = 9fb085062d52c365c9d7aa7a9b2f973ac49123cd
MINUI_SITE = https://github.com/minime-os/minui.git
MINUI_SITE_METHOD = git
MINUI_LICENSE = See upstream
MINUI_LICENSE_FILES = README.md

MINUI_DEPENDENCIES = dbus libretro-common lz4 sdl2 sdl2_image sdl2_ttf zlib
MINUI_INSTALL_IMAGES = YES

# Minime SD-card layout contract.  These values are baked into the UI binaries
# at build time so that the UI package does not need to know the firmware
# internals at runtime.  S60ui still exports the same values for subprocesses.
MINUI_SDCARD_PATH = /mnt/sdcard
MINUI_UI_PATH = $(MINUI_SDCARD_PATH)/.ui
MINUI_CORES_PATH = $(MINUI_SDCARD_PATH)/.cores

MINUI_CPPFLAGS = \
	-DSDCARD_PATH=\"$(MINUI_SDCARD_PATH)\" \
	-DSYSTEM_PATH=\"$(MINUI_UI_PATH)\" \
	-DROOT_SYSTEM_PATH=\"$(MINUI_UI_PATH)\" \
	-DRES_PATH=\"$(MINUI_UI_PATH)/res\" \
	-DCORE_CONFIGS_PATH=\"$(MINUI_CORES_PATH)/config\" \
	-DCORE_LIBS_PATH=\"$(MINUI_CORES_PATH)\" \
	-DUSERDATA_PATH=\"$(MINUI_UI_PATH)/config\" \
	-DSHARED_USERDATA_PATH=\"$(MINUI_SDCARD_PATH)/saves\" \
	-DCORES_PATH=\"$(MINUI_CORES_PATH)\" \
	-DROMS_PATH=\"$(MINUI_SDCARD_PATH)/roms\" \
	-DBIOS_PATH=\"$(MINUI_SDCARD_PATH)/bios\" \
	-DSAVES_PATH=\"$(MINUI_SDCARD_PATH)/saves\" \
	-DPLATFORM=\"$(MINUI_PLATFORM_NAME)\" \
	-DBUILD_DATE=\"$(MINUI_BUILD_DATE)\" \
	-DBUILD_HASH=\"$(MINUI_BUILD_HASH)\"

MINUI_SRC_DIR = $(@D)/src
MINUI_ASSETS_DIR = $(@D)/assets
MINUI_BUILD_DIR = $(@D)/build-minime
MINUI_PLATFORM_DIR = $(MINUI_SRC_DIR)/platform/rg35xxplus
MINUI_PLATFORM_NAME = rg35xxplus
MINUI_TIMEZONE_SRC = $(MINUI_ASSETS_DIR)/timezones/minui.tzs
MINUI_ZIC = $(shell command -v zic 2>/dev/null || echo /usr/sbin/zic)
MINUI_BUILD_DATE = $(shell date +%Y.%m.%d)
MINUI_BUILD_HASH = $(shell git -C $(@D) rev-parse --short HEAD 2>/dev/null || echo clean-start)
MINUI_RUNTIME_RPATH = -Wl,-rpath,'$$ORIGIN'

MINUI_DBUS_CFLAGS = -I$(STAGING_DIR)/usr/include/dbus-1.0 \
	-I$(STAGING_DIR)/usr/lib/dbus-1.0/include
MINUI_LIBRETRO_CFLAGS = -I$(STAGING_DIR)/usr/include
MINUI_LZ4_CFLAGS = -I$(STAGING_DIR)/usr/include
MINUI_LZ4_LDFLAGS = -L$(STAGING_DIR)/usr/lib

define MINUI_BUILD_CMDS
	mkdir -p $(MINUI_BUILD_DIR)

	# libmsettings
	$(TARGET_CC) $(TARGET_CFLAGS) -fPIC \
		-I$(MINUI_SRC_DIR)/libmsettings \
		-c $(MINUI_SRC_DIR)/libmsettings/msettings.c \
		-o $(MINUI_BUILD_DIR)/msettings.o
	$(TARGET_CC) $(TARGET_LDFLAGS) -shared -Wl,-soname,libmsettings.so \
		-o $(MINUI_BUILD_DIR)/libmsettings.so \
		$(MINUI_BUILD_DIR)/msettings.o -ldl -lrt

	# keymon
	$(TARGET_CC) $(TARGET_CFLAGS) \
		-I$(MINUI_SRC_DIR)/common \
		-I$(MINUI_SRC_DIR)/libmsettings \
		-I$(MINUI_PLATFORM_DIR) \
		$(MINUI_SRC_DIR)/keymon/keymon.c \
		-o $(MINUI_BUILD_DIR)/keymon \
		$(TARGET_LDFLAGS) $(MINUI_RUNTIME_RPATH) -L$(MINUI_BUILD_DIR) \
		-lmsettings -lpthread -lrt -ldl

	# minarch
	$(TARGET_CC) $(TARGET_CFLAGS) $(MINUI_CPPFLAGS) -fomit-frame-pointer -std=gnu99 \
		$(MINUI_LIBRETRO_CFLAGS) \
		$(MINUI_LZ4_CFLAGS) \
		-I$(MINUI_SRC_DIR)/minarch \
		-I$(MINUI_SRC_DIR)/common \
		-I$(MINUI_SRC_DIR)/libmsettings \
		-I$(MINUI_PLATFORM_DIR) \
		-DUSE_SDL2 \
		$(MINUI_SRC_DIR)/minarch/main.c \
		$(MINUI_SRC_DIR)/minarch/core.c \
		$(MINUI_SRC_DIR)/minarch/content.c \
		$(MINUI_SRC_DIR)/minarch/config.c \
		$(MINUI_SRC_DIR)/minarch/options.c \
		$(MINUI_SRC_DIR)/minarch/input.c \
		$(MINUI_SRC_DIR)/minarch/rewind.c \
		$(MINUI_SRC_DIR)/minarch/video.c \
		$(MINUI_SRC_DIR)/minarch/menu.c \
		$(MINUI_SRC_DIR)/common/scaler.c \
		$(MINUI_SRC_DIR)/common/utils.c \
		$(MINUI_SRC_DIR)/common/api.c \
		$(MINUI_SRC_DIR)/common/core_registry.c \
		$(MINUI_PLATFORM_DIR)/platform.c \
		-o $(MINUI_BUILD_DIR)/minarch \
		$(TARGET_LDFLAGS) $(MINUI_RUNTIME_RPATH) $(MINUI_LZ4_LDFLAGS) \
		-L$(MINUI_BUILD_DIR) -ldl -llz4 -lmsettings -lSDL2 -lSDL2_image -lSDL2_ttf \
		-lpthread -lm -lz

	# minui main UI
	$(TARGET_CC) $(TARGET_CFLAGS) $(MINUI_CPPFLAGS) -fomit-frame-pointer -std=gnu99 \
		$(MINUI_DBUS_CFLAGS) \
		-I$(MINUI_SRC_DIR)/main \
		-I$(MINUI_SRC_DIR)/settings \
		-I$(MINUI_SRC_DIR)/ui \
		-I$(MINUI_SRC_DIR)/common \
		-I$(MINUI_SRC_DIR)/libmsettings \
		-I$(MINUI_PLATFORM_DIR) \
		-DUSE_SDL2 \
		$(MINUI_SRC_DIR)/main/main.c \
		$(MINUI_SRC_DIR)/settings/settings.c \
		$(MINUI_SRC_DIR)/settings/menu.c \
		$(MINUI_SRC_DIR)/settings/jobs.c \
		$(MINUI_SRC_DIR)/settings/timezone.c \
		$(MINUI_SRC_DIR)/settings/wifi_backend.c \
		$(MINUI_SRC_DIR)/settings/bt_backend.c \
		$(MINUI_SRC_DIR)/settings/about.c \
		$(MINUI_SRC_DIR)/settings/power.c \
		$(MINUI_SRC_DIR)/settings/time.c \
		$(MINUI_SRC_DIR)/settings/wifi.c \
		$(MINUI_SRC_DIR)/settings/bt.c \
		$(MINUI_SRC_DIR)/settings/controls.c \
		$(MINUI_SRC_DIR)/ui/badge.c \
		$(MINUI_SRC_DIR)/ui/list.c \
		$(MINUI_SRC_DIR)/ui/dialog.c \
		$(MINUI_SRC_DIR)/ui/keyboard.c \
		$(MINUI_SRC_DIR)/common/scaler.c \
		$(MINUI_SRC_DIR)/common/utils.c \
		$(MINUI_SRC_DIR)/common/api.c \
		$(MINUI_SRC_DIR)/common/core_registry.c \
		$(MINUI_PLATFORM_DIR)/platform.c \
		-o $(MINUI_BUILD_DIR)/minui \
		$(TARGET_LDFLAGS) $(MINUI_RUNTIME_RPATH) -L$(MINUI_BUILD_DIR) \
		-ldbus-1 -ldl -lmsettings -lSDL2 -lSDL2_image -lSDL2_ttf -lpthread -lm -lz

	# optional boot splash helper
	if [ -f $(MINUI_SRC_DIR)/show/show.c ]; then \
		$(TARGET_CC) $(TARGET_CFLAGS) \
			$(MINUI_SRC_DIR)/show/show.c \
			-o $(MINUI_BUILD_DIR)/minui-show \
			$(TARGET_LDFLAGS) -lSDL2 -lSDL2_image -lrt -ldl; \
	fi
endef

define MINUI_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.ui/bin
	mkdir -p $(BINARIES_DIR)/ui/.ui/res
	mkdir -p $(BINARIES_DIR)/ui/.ui/config
	mkdir -p $(BINARIES_DIR)/ui/.cores/config

	cp -f $(MINUI_BUILD_DIR)/minui $(BINARIES_DIR)/ui/.ui/bin/
	cp -f $(MINUI_BUILD_DIR)/minarch $(BINARIES_DIR)/ui/.ui/bin/
	cp -f $(MINUI_BUILD_DIR)/libmsettings.so $(BINARIES_DIR)/ui/.ui/bin/
	$(if $(wildcard $(MINUI_BUILD_DIR)/minui-show), \
		cp -f $(MINUI_BUILD_DIR)/minui-show $(BINARIES_DIR)/ui/.ui/bin/)
	$(if $(wildcard $(MINUI_BUILD_DIR)/keymon), \
		cp -f $(MINUI_BUILD_DIR)/keymon $(BINARIES_DIR)/ui/.ui/bin/)

	$(HOST_DIR)/bin/patchelf --set-rpath '$$ORIGIN' $(BINARIES_DIR)/ui/.ui/bin/minui || true
	$(HOST_DIR)/bin/patchelf --set-rpath '$$ORIGIN' $(BINARIES_DIR)/ui/.ui/bin/minarch || true

	# shared MinUI assets
	if [ -d $(MINUI_ASSETS_DIR)/res ]; then \
		cp -a $(MINUI_ASSETS_DIR)/res/. $(BINARIES_DIR)/ui/.ui/res/; \
	fi

	# launcher entry point; UI-specific env setup
	printf '%s\n' \
		'#!/bin/sh' \
		'export SDCARD_PATH=/mnt/sdcard' \
		'export SYSTEM_PATH="$$SDCARD_PATH/.ui"' \
		'export USERDATA_PATH="$$SYSTEM_PATH/config"' \
		'export CORES_PATH="$$SDCARD_PATH/.cores"' \
		'export LD_LIBRARY_PATH="$$SYSTEM_PATH/bin"' \
		'export HOME="$$SDCARD_PATH"' \
		'killall keymon 2>/dev/null || true' \
		'[ ! -x "$$SYSTEM_PATH/bin/keymon" ] || "$$SYSTEM_PATH/bin/keymon" > /tmp/keymon.log 2>&1 &' \
		'exec "$$SYSTEM_PATH/bin/minui"' \
		> $(BINARIES_DIR)/ui/.ui/launch.sh
	chmod +x $(BINARIES_DIR)/ui/.ui/launch.sh

	# core default configs and controller binds
	if [ -d $(MINUI_ASSETS_DIR)/cores ]; then \
		cp -a $(MINUI_ASSETS_DIR)/cores/. $(BINARIES_DIR)/ui/.cores/config/; \
	fi
endef

$(eval $(generic-package))
