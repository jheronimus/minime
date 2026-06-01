include $(sort $(wildcard $(BR2_EXTERNAL_MINIME_PATH)/package/*/*.mk))

# Hooks to copy custom DTS files and patch base DTS file in Linux kernel
define MINIME_COPY_DTS
	if [ -d $(BR2_EXTERNAL_MINIME_PATH)/board/h700/dts ]; then \
		cp $(BR2_EXTERNAL_MINIME_PATH)/board/h700/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/allwinner/; \
	fi
endef
LINUX_PRE_PATCH_HOOKS += MINIME_COPY_DTS


define MINIME_PATCH_LINUX_CONFIG
	sed -i 's|__SIMON_BOARD_FIRMWARE_DIR__|$(BR2_EXTERNAL_MINIME_PATH)/board/h700/firmware|g' $(LINUX_DIR)/.config
endef
LINUX_POST_CONFIGURE_HOOKS += MINIME_PATCH_LINUX_CONFIG

SDL2_AUTORECONF = YES

ifeq ($(BR2_PACKAGE_LIBMALI),y)
SDL2_CONF_OPTS += --enable-video-mali
else
SDL2_CONF_OPTS += --disable-video-mali
endif

define SDL2_RESTORE_CONFIG_H
	mv $(@D)/include/SDL_config.h $(@D)/include/SDL_config.h.orig
	(echo '#ifndef SDL_config_h_'; \
	 echo '#define SDL_config_h_'; \
	 echo '#include "SDL_platform.h"'; \
	 cat $(@D)/include/SDL_config.h.orig; \
	 echo '#endif /* SDL_config_h_ */') > $(@D)/include/SDL_config.h
endef
SDL2_POST_CONFIGURE_HOOKS += SDL2_RESTORE_CONFIG_H

define SDL2_ADD_MALI_SOURCES
	$(SED) '/AC_DEFINE(SDL_VIDEO_DRIVER_MALI/a \            SOURCES="$$SOURCES $$srcdir/src/video/mali-fbdev/*.c"' $(@D)/configure.ac
	python3 $(BR2_EXTERNAL_MINIME_PATH)/../scripts/patch_mali_dma_heap.py $(@D)
endef
SDL2_POST_PATCH_HOOKS += SDL2_ADD_MALI_SOURCES
