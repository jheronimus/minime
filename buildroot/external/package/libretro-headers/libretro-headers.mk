################################################################################
#
# libretro-headers
#
################################################################################

LIBRETRO_HEADERS_VERSION = 52193838ab224f23129b4be5a571d523ca566ac8
LIBRETRO_HEADERS_SITE = $(call github,libretro,libretro-common,$(LIBRETRO_HEADERS_VERSION))
LIBRETRO_HEADERS_LICENSE = MIT
LIBRETRO_HEADERS_LICENSE_FILES = include/libretro.h
LIBRETRO_HEADERS_INSTALL_STAGING = YES

define LIBRETRO_HEADERS_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/libretro.h \
		$(STAGING_DIR)/usr/include/libretro.h
endef

$(eval $(generic-package))
