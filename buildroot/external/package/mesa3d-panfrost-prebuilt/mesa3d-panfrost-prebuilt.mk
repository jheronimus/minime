################################################################################
#
# mesa3d-panfrost-prebuilt
#
################################################################################

MESA3D_PANFROST_PREBUILT_VERSION = 25.0.7
MESA3D_PANFROST_PREBUILT_SITE = $(call github,jheronimus,panfrost-prebuilts,v$(MESA3D_PANFROST_PREBUILT_VERSION))
MESA3D_PANFROST_PREBUILT_LICENSE = MIT, GPL-2.0, LGPL-2.1
MESA3D_PANFROST_PREBUILT_LICENSE_FILES = COPYING

define MESA3D_PANFROST_PREBUILT_INSTALL_TARGET_CMDS
	# Extract precompiled libraries directly into /usr/lib/panfrost on the target
	mkdir -p $(TARGET_DIR)/usr/lib/panfrost
	tar -C $(TARGET_DIR)/usr/lib/panfrost --strip-components=1 \
		-xzf $(MESA3D_PANFROST_PREBUILT_DIR)/panfrost-prebuilts-v$(MESA3D_PANFROST_PREBUILT_VERSION).tar.gz
endef

$(eval $(generic-package))
