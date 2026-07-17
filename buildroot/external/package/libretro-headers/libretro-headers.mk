################################################################################
#
# libretro-headers
#
################################################################################

LIBRETRO_HEADERS_VERSION = 48930e4b687028055d137de28874da6adb0fae5f
LIBRETRO_HEADERS_SITE = $(call github,libretro,libretro-common,$(LIBRETRO_HEADERS_VERSION))
LIBRETRO_HEADERS_LICENSE = MIT
LIBRETRO_HEADERS_LICENSE_FILES = include/libretro.h
LIBRETRO_HEADERS_INSTALL_STAGING = YES

define LIBRETRO_HEADERS_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/libretro.h \
		$(STAGING_DIR)/usr/include/libretro.h
endef

$(eval $(generic-package))
