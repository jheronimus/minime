################################################################################
#
# retroarch-cores
#
################################################################################

RETROARCH_CORES_VERSION = 1.0
RETROARCH_CORES_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/retroarch-cores
RETROARCH_CORES_SITE_METHOD = local
RETROARCH_CORES_SOURCE =
RETROARCH_CORES_DEPENDENCIES = zlib

RETROARCH_CORES_INSTALL_IMAGES = YES

define RETROARCH_CORES_BUILD_CMDS
	mkdir -p $(@D)/src

	# 1. Nestopia
	if [ ! -d $(@D)/src/nestopia ]; then \
		git clone --depth 1 https://github.com/libretro/nestopia.git $(@D)/src/nestopia ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/nestopia/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 2. Gambatte
	if [ ! -d $(@D)/src/gambatte ]; then \
		git clone --depth 1 https://github.com/libretro/gambatte-libretro.git $(@D)/src/gambatte ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/gambatte/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 3. mGBA
	if [ ! -d $(@D)/src/mgba ]; then \
		git clone --depth 1 https://github.com/libretro/mgba.git $(@D)/src/mgba ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/mgba/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 4. Genesis Plus GX
	if [ ! -d $(@D)/src/genesis_plus_gx ]; then \
		git clone --depth 1 https://github.com/libretro/Genesis-Plus-GX.git $(@D)/src/genesis_plus_gx ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/genesis_plus_gx -f Makefile.libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 5. Beetle PCE Fast
	if [ ! -d $(@D)/src/beetle_pce_fast ]; then \
		git clone --depth 1 https://github.com/libretro/beetle-pce-fast-libretro.git $(@D)/src/beetle_pce_fast ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/beetle_pce_fast \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 6. Snes9x
	if [ ! -d $(@D)/src/snes9x ]; then \
		git clone --depth 1 https://github.com/libretro/snes9x.git $(@D)/src/snes9x ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/snes9x/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix

	# 7. PCSX-ReARMed
	if [ ! -d $(@D)/src/pcsx_rearmed ]; then \
		git clone --depth 1 https://github.com/libretro/pcsx_rearmed.git $(@D)/src/pcsx_rearmed ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/pcsx_rearmed -f Makefile.libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix ARCH=arm64

	# 8. yabasanshiro
	if [ ! -d $(@D)/src/yabasanshiro ]; then \
		git clone --depth 1 -b yabasanshiro https://github.com/libretro/yabause.git $(@D)/src/yabasanshiro ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/yabasanshiro/yabause/src/libretro -f Makefile.libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix DYNAREC_DEVMIYAX=1 FORCE_GLES=1

	# 9. FBNeo
	if [ ! -d $(@D)/src/fbneo ]; then \
		git clone --depth 1 https://github.com/libretro/FBNeo.git $(@D)/src/fbneo ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/fbneo/src/burner/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" LD="$(TARGET_LD)" \
		CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
		platform=unix profile=performance
endef

define RETROARCH_CORES_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.retroarch/cores
	mkdir -p $(BINARIES_DIR)/ui/.retroarch/info
	mkdir -p $(BINARIES_DIR)/ui/bios

	# Install cores
	cp -f $(@D)/src/nestopia/libretro/nestopia_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/gambatte/libretro/gambatte_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/mgba/libretro/mgba_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/genesis_plus_gx/genesis_plus_gx_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/beetle_pce_fast/mednafen_pce_fast_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/snes9x/libretro/snes9x_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/pcsx_rearmed/pcsx_rearmed_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/yabasanshiro/yabause/src/libretro/yabasanshiro_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/
	cp -f $(@D)/src/fbneo/src/burner/libretro/fbneo_libretro.so $(BINARIES_DIR)/ui/.retroarch/cores/

	# Install info files
	cp -f $(BR2_EXTERNAL_MINIME_PATH)/package/retroarch-cores/info/*.info $(BINARIES_DIR)/ui/.retroarch/info/
endef

$(eval $(generic-package))
