################################################################################
#
# retroarch
#
################################################################################

RETROARCH_VERSION = v1.22.2
RETROARCH_SITE = https://github.com/libretro/RetroArch.git
RETROARCH_SITE_METHOD = git
RETROARCH_DEPENDENCIES = sdl2 alsa-lib libegl libgles zlib libretro-cores

define RETROARCH_CONFIGURE_CMDS
	cd $(@D) && $(TARGET_MAKE_ENV) $(TARGET_CONFIGURE_OPTS) ./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--disable-gl \
		--enable-egl \
		--enable-gles \
		--enable-kms \
		--disable-x11 \
		--disable-wayland \
		--enable-alsa \
		--disable-ffmpeg \
		--enable-zlib \
		--enable-floathard \
		--enable-neon
endef

define RETROARCH_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define RETROARCH_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install
endef

RETROARCH_INSTALL_IMAGES = YES

define RETROARCH_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.ui/retroarch
	cp -f $(BR2_EXTERNAL_MINIME_PATH)/package/retroarch/retroarch.cfg $(BINARIES_DIR)/ui/.ui/retroarch/retroarch.cfg
endef

$(eval $(generic-package))
