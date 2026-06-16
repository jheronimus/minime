################################################################################
#
# bootsplash
#
################################################################################

BOOTSPLASH_VERSION = 1.0.1
BOOTSPLASH_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/bootsplash/src
BOOTSPLASH_SITE_METHOD = local
BOOTSPLASH_LICENSE = MIT
BOOTSPLASH_LICENSE_FILES = LICENSE

BOOTSPLASH_DEPENDENCIES = sdl2

define BOOTSPLASH_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=gnu11 -O2 \
		-I$(STAGING_DIR)/usr/include/SDL2 -D_REENTRANT \
		-o $(@D)/bootsplash \
		$(wildcard $(@D)/*.c) \
		-L$(STAGING_DIR)/usr/lib -lSDL2 -lm
endef

define BOOTSPLASH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bootsplash $(TARGET_DIR)/usr/bin/bootsplash
endef

$(eval $(generic-package))
