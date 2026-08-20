################################################################################
#
# bt-mirror
#
################################################################################

BT_MIRROR_VERSION = local
BT_MIRROR_SITE = $(MINIME_ROOT)/src/bt-mirror
BT_MIRROR_SITE_METHOD = local
BT_MIRROR_LICENSE = MIT

define BT_MIRROR_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define BT_MIRROR_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bt-mirror $(TARGET_DIR)/usr/bin/bt-mirror
endef

$(eval $(generic-package))
