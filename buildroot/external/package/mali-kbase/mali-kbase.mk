################################################################################
#
# mali-kbase
#
################################################################################

MALI_KBASE_VERSION = 39da994bb6fc8819e5e8c1873907dd21d17e53c1
MALI_KBASE_SITE = $(call github,rocknix,mali_kbase,$(MALI_KBASE_VERSION))
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

define MALI_KBASE_PATCH_DRIVERS
	python3 $(BR2_EXTERNAL_MINIME_PATH)/package/mali-kbase/patch-drivers.py $(@D)
endef
MALI_KBASE_POST_PATCH_HOOKS += MALI_KBASE_PATCH_DRIVERS

$(eval $(kernel-module))
$(eval $(generic-package))
