################################################################################
#
# mali-kbase
#
################################################################################

MALI_KBASE_VERSION = fb816bb1533cc1447843375314561ce599defae7
MALI_KBASE_SITE = $(call github,jheronimus,mali_kbase,$(MALI_KBASE_VERSION))
MALI_KBASE_LICENSE = GPL-2.0
MALI_KBASE_LICENSE_FILES = COPYING

MALI_KBASE_MODULE_SUBDIRS = product/kernel/drivers/gpu/arm/midgard

MALI_KBASE_MODULE_MAKE_OPTS = \
	CONFIG_MALI_MIDGARD=m \
	CONFIG_MALI_PLATFORM_DEVICETREE=y \
	CONFIG_MALI_PLATFORM_NAME=devicetree \
	CONFIG_MALI_REAL_HW=y \
	CONFIG_MALI_DEVFREQ=y \
	CONFIG_MALI_BACKEND=gpu \
	EXTRA_CFLAGS="-I$(@D)/product/kernel/include"

$(eval $(kernel-module))
$(eval $(generic-package))

