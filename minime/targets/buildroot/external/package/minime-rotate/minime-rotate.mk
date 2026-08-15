################################################################################
#
# minime-rotate
#
################################################################################

MINIME_ROTATE_VERSION = local
MINIME_ROTATE_SITE = $(MINIME_ROOT)/src/display
MINIME_ROTATE_SITE_METHOD = local
MINIME_ROTATE_LICENSE = MIT

define MINIME_ROTATE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define MINIME_ROTATE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/minime-rotate $(TARGET_DIR)/usr/bin/minime-rotate
endef

$(eval $(generic-package))
