################################################################################
#
# libretro-cores
#
################################################################################

LIBRETRO_CORES_VERSION = 1.6
LIBRETRO_CORES_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/libretro-cores
LIBRETRO_CORES_SITE_METHOD = local
LIBRETRO_CORES_SOURCE =
LIBRETRO_CORES_DEPENDENCIES = zlib

LIBRETRO_CORES_INSTALL_IMAGES = YES

define LIBRETRO_CORES_BUILD_CMDS
	mkdir -p $(@D)/src

	# 1. FCEUmm (NES)
	if [ ! -d $(@D)/src/fceumm ]; then \
		git clone --depth 1 https://github.com/libretro/libretro-fceumm.git $(@D)/src/fceumm ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/fceumm \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 2. Gambatte (GB/GBC)
	if [ ! -d $(@D)/src/gambatte ]; then \
		git clone --depth 1 https://github.com/libretro/gambatte-libretro.git $(@D)/src/gambatte ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/gambatte \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 3. mGBA (GBA)
	if [ ! -d $(@D)/src/mgba ]; then \
		git clone --depth 1 https://github.com/libretro/mgba.git $(@D)/src/mgba ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/mgba \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 4. Genesis Plus GX (Genesis / Game Gear / Master System)
	if [ ! -d $(@D)/src/genesis_plus_gx ]; then \
		git clone --depth 1 https://github.com/libretro/Genesis-Plus-GX.git $(@D)/src/genesis_plus_gx ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/genesis_plus_gx -f Makefile.libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 5. Beetle PCE Fast (PC Engine)
	if [ ! -d $(@D)/src/beetle_pce_fast ]; then \
		git clone --depth 1 https://github.com/libretro/beetle-pce-fast-libretro.git $(@D)/src/beetle_pce_fast ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/beetle_pce_fast \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 6. Snes9x (SNES)
	if [ ! -d $(@D)/src/snes9x ]; then \
		git clone --depth 1 https://github.com/libretro/snes9x.git $(@D)/src/snes9x ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/snes9x/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 7. PCSX-ReARMed (PlayStation)
	if [ ! -d $(@D)/src/pcsx_rearmed ]; then \
		git clone --depth 1 https://github.com/libretro/pcsx_rearmed.git $(@D)/src/pcsx_rearmed ; \
		sed -i 's/ifeq "$(PLATFORM)" "libretro"/ifneq "$(platform)" ""/' $(@D)/src/pcsx_rearmed/Makefile.libretro ; \
		sed -i 's/vfs_implementation.o/vfs_implementation.o deps\/libretro-common\/lists\/dir_list.o deps\/libretro-common\/file\/retro_dirent.o deps\/libretro-common\/compat\/compat_strcasestr.o/' $(@D)/src/pcsx_rearmed/Makefile ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/pcsx_rearmed -f Makefile.libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix ARCH=arm64

	# 8. Beetle Saturn (Sega Saturn)
	if [ ! -d $(@D)/src/beetle_saturn ]; then \
		git clone --depth 1 https://github.com/libretro/beetle-saturn-libretro.git $(@D)/src/beetle_saturn ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/beetle_saturn \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix

	# 9. FBNeo (Arcade)
	if [ ! -d $(@D)/src/fbneo ]; then \
		git clone --depth 1 https://github.com/libretro/FBNeo.git $(@D)/src/fbneo ; \
	fi
	$(TARGET_MAKE_ENV) CFLAGS="$(TARGET_CFLAGS) -ffast-math" CXXFLAGS="$(TARGET_CXXFLAGS) -ffast-math" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(@D)/src/fbneo/src/burner/libretro \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		platform=unix
endef

define LIBRETRO_CORES_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.cores
	mkdir -p $(BINARIES_DIR)/ui/.cores/config/info

	# Install cores
	cp -f $(@D)/src/fceumm/fceumm_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/gambatte/gambatte_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/mgba/mgba_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/genesis_plus_gx/genesis_plus_gx_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/beetle_pce_fast/mednafen_pce_fast_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/snes9x/libretro/snes9x_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/pcsx_rearmed/pcsx_rearmed_libretro.so $(BINARIES_DIR)/ui/.cores/
	cp -f $(@D)/src/beetle_saturn/mednafen_saturn_libretro.so $(BINARIES_DIR)/ui/.cores/beetle_saturn_libretro.so
	cp -f $(@D)/src/fbneo/src/burner/libretro/fbneo_libretro.so $(BINARIES_DIR)/ui/.cores/

	# Install info files
	cp -f $(BR2_EXTERNAL_MINIME_PATH)/package/libretro-cores/info/*.info $(BINARIES_DIR)/ui/.cores/config/info/
endef

$(eval $(generic-package))
