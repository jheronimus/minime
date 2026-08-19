################################################################################
#
# bootsplash
#
################################################################################

BOOTSPLASH_VERSION = local
BOOTSPLASH_SITE = $(MINIME_ROOT)/src/bootsplash
BOOTSPLASH_SITE_METHOD = local
BOOTSPLASH_LICENSE = MIT

define BOOTSPLASH_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define BOOTSPLASH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bootsplash $(TARGET_DIR)/usr/bin/bootsplash
endef

$(eval $(generic-package))
