################################################################################
#
# retroarch-frontend
#
################################################################################

RETROARCH_FRONTEND_VERSION = v1.19.1
RETROARCH_FRONTEND_SITE = https://github.com/libretro/RetroArch.git
RETROARCH_FRONTEND_SITE_METHOD = git
RETROARCH_FRONTEND_DEPENDENCIES = sdl2 alsa-lib libegl libgles zlib retroarch-cores

define RETROARCH_FRONTEND_CONFIGURE_CMDS
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

define RETROARCH_FRONTEND_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define RETROARCH_FRONTEND_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install
endef

RETROARCH_FRONTEND_INSTALL_IMAGES = YES

define RETROARCH_FRONTEND_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.retroarch
	cp -f $(BR2_EXTERNAL_MINIME_PATH)/package/retroarch-frontend/retroarch.cfg $(BINARIES_DIR)/ui/.retroarch/retroarch.cfg
endef

$(eval $(generic-package))
