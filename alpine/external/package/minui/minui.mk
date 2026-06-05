################################################################################
#
# minui
#
################################################################################

MINUI_VERSION = main
MINUI_SITE = https://github.com/jheronimus/MinUI.git
MINUI_SITE_METHOD = git
MINUI_LICENSE = See upstream
MINUI_LICENSE_FILES = README.md

MINUI_DEPENDENCIES = dbus host-patchelf lz4 sdl2 sdl2_image sdl2_ttf zlib

MINUI_INSTALL_IMAGES = YES

# Pass DBus CFLAGS for target architecture
MINUI_DBUS_CFLAGS = -I$(STAGING_DIR)/usr/include/dbus-1.0 -I$(STAGING_DIR)/usr/lib/dbus-1.0/include

# We wrap CFLAGS and LDFLAGS inside CC and CXX to avoid wiping out the package's
# internal makefiles' libraries (like -lSDL2, -lmsettings) which would happen
# if we overrode CFLAGS/LDFLAGS on the command line.
define MINUI_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/workspace \
		CC="$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $(MINUI_DBUS_CFLAGS) -ldbus-1" \
		CXX="$(TARGET_CXX) $(TARGET_CXXFLAGS) $(TARGET_LDFLAGS)" \
		PLATFORM=minime \
		UNION_PLATFORM=minime \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		PREFIX="$(STAGING_DIR)/usr" \
		BUILD_EXTRAS=$(if $(BR2_PACKAGE_MINUI_EXTRAS),y,n) \
		all
endef

define MINUI_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.system/bin
	mkdir -p $(BINARIES_DIR)/ui/.system/cores

	# Install main launcher binary
	cp -f $(@D)/workspace/all/minui/build/minime/minui.elf $(BINARIES_DIR)/ui/.system/bin/minui
	cp -f $(@D)/workspace/all/minarch/build/minime/minarch.elf $(BINARIES_DIR)/ui/.system/bin/minarch
	cp -f $(@D)/workspace/minime/libmsettings/libmsettings.so $(BINARIES_DIR)/ui/.system/bin/
	$(HOST_DIR)/bin/patchelf --set-rpath '$$ORIGIN' $(BINARIES_DIR)/ui/.system/bin/minui
	$(HOST_DIR)/bin/patchelf --set-rpath '$$ORIGIN' $(BINARIES_DIR)/ui/.system/bin/minarch

	# Install shared MinUI assets
	mkdir -p $(BINARIES_DIR)/ui/.system/res
	cp -rp $(@D)/skeleton/SYSTEM/res/. $(BINARIES_DIR)/ui/.system/res/

	# Install stock (base) RetroArch cores
	cp -f $(@D)/workspace/minime/cores/output/fceumm_libretro.so $(BINARIES_DIR)/ui/.system/cores/
	cp -f $(@D)/workspace/minime/cores/output/gambatte_libretro.so $(BINARIES_DIR)/ui/.system/cores/
	cp -f $(@D)/workspace/minime/cores/output/gpsp_libretro.so $(BINARIES_DIR)/ui/.system/cores/
	cp -f $(@D)/workspace/minime/cores/output/picodrive_libretro.so $(BINARIES_DIR)/ui/.system/cores/
	cp -f $(@D)/workspace/minime/cores/output/snes9x2005_plus_libretro.so $(BINARIES_DIR)/ui/.system/cores/
	cp -f $(@D)/workspace/minime/cores/output/pcsx_rearmed_libretro.so $(BINARIES_DIR)/ui/.system/cores/

	# Install Clock tool
	mkdir -p $(BINARIES_DIR)/ui/Tools/Clock.pak
	cp -f $(@D)/workspace/all/clock/build/minime/clock.elf $(BINARIES_DIR)/ui/Tools/Clock.pak/
	printf '%s\n' '#!/bin/sh' 'cd $$(dirname "$$0")' 'exec ./clock.elf' > $(BINARIES_DIR)/ui/Tools/Clock.pak/launch.sh
	chmod +x $(BINARIES_DIR)/ui/Tools/Clock.pak/launch.sh

	# Install Settings tool
	mkdir -p $(BINARIES_DIR)/ui/Tools/Settings.pak
	cp -f $(@D)/workspace/all/settings/build/minime/settings.elf $(BINARIES_DIR)/ui/Tools/Settings.pak/
	printf '%s\n' '#!/bin/sh' 'cd $$(dirname "$$0")' 'exec ./settings.elf' > $(BINARIES_DIR)/ui/Tools/Settings.pak/launch.sh
	chmod +x $(BINARIES_DIR)/ui/Tools/Settings.pak/launch.sh

	# Install extras if enabled
	$(if $(filter y,$(BR2_PACKAGE_MINUI_EXTRAS)),\
		cp -f $(@D)/workspace/minime/cores/output/fake08_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/mgba_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/mednafen_pce_fast_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/pokemini_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/race_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/mednafen_supafaust_libretro.so $(BINARIES_DIR)/ui/.system/cores/ ; \
		cp -f $(@D)/workspace/minime/cores/output/mednafen_vb_libretro.so $(BINARIES_DIR)/ui/.system/cores/ \
	)
endef

$(eval $(generic-package))
