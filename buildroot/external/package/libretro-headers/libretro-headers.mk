################################################################################
#
# libretro-headers
#
################################################################################

LIBRETRO_HEADERS_VERSION = 9e2af2c23ff2595f096e2f591ea49a9bcb65401d
LIBRETRO_HEADERS_SITE = $(call github,libretro,libretro-common,$(LIBRETRO_HEADERS_VERSION))
LIBRETRO_HEADERS_LICENSE = MIT
LIBRETRO_HEADERS_LICENSE_FILES = include/libretro.h
LIBRETRO_HEADERS_INSTALL_STAGING = YES

define LIBRETRO_HEADERS_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/libretro.h \
		$(STAGING_DIR)/usr/include/libretro.h
endef

$(eval $(generic-package))
