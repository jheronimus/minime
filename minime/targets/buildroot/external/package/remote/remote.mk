################################################################################
#
# remote
#
################################################################################

REMOTE_VERSION = local
REMOTE_SITE = $(MINIME_ROOT)/src/remote
REMOTE_SITE_METHOD = local
REMOTE_LICENSE = MIT

define REMOTE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define REMOTE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/remote $(TARGET_DIR)/usr/bin/remote
endef

$(eval $(generic-package))
