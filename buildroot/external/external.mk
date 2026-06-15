include $(sort $(wildcard $(BR2_EXTERNAL_MINIME_PATH)/package/*/*.mk))

# Hooks to copy custom DTS files and patch base DTS file in Linux kernel
define MINIME_COPY_DTS
	if [ -d $(BR2_EXTERNAL_MINIME_PATH)/board/h700/dts ]; then \
		cp $(BR2_EXTERNAL_MINIME_PATH)/board/h700/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/allwinner/; \
	fi
	if [ -d $(BR2_EXTERNAL_MINIME_PATH)/board/rk3326/dts ]; then \
		cp $(BR2_EXTERNAL_MINIME_PATH)/board/rk3326/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/rockchip/; \
		echo "dtb-\$$(CONFIG_ARCH_ROCKCHIP) += rk3326-anbernic-rg351p.dtb" >> $(LINUX_DIR)/arch/arm64/boot/dts/rockchip/Makefile; \
		echo "dtb-\$$(CONFIG_ARCH_ROCKCHIP) += rk3326-anbernic-rg351mp.dtb" >> $(LINUX_DIR)/arch/arm64/boot/dts/rockchip/Makefile; \
	fi
endef
LINUX_PRE_PATCH_HOOKS += MINIME_COPY_DTS


define MINIME_PATCH_LINUX_CONFIG
	sed -i 's|__MINIME_BOARD_FIRMWARE_DIR__|$(BR2_EXTERNAL_MINIME_PATH)/board/h700/firmware|g' $(LINUX_DIR)/.config
	sed -i 's|__MINIME_COMMON_FIRMWARE_DIR__|$(BR2_EXTERNAL_MINIME_PATH)/board/common/firmware|g' $(LINUX_DIR)/.config
endef
LINUX_POST_CONFIGURE_HOOKS += MINIME_PATCH_LINUX_CONFIG

SDL2_MALI_PATCHES = $(strip $(foreach dir,$(call qstrip,$(BR2_GLOBAL_PATCH_DIR)),$(wildcard $(dir)/sdl2/*add-mali-fbdev*)))

ifeq ($(SDL2_MALI_PATCHES),)
SDL2_CONF_OPTS += --disable-video-mali
else
ifeq ($(BR2_PACKAGE_LIBMALI),y)
SDL2_CONF_OPTS += --enable-video-mali
else
SDL2_CONF_OPTS += --disable-video-mali
endif
endif

define SDL2_ADD_MALI_SOURCES
	if [ -d $(@D)/src/video/mali-fbdev ]; then \
		$(SED) '/AC_DEFINE(SDL_VIDEO_DRIVER_MALI/a \            SOURCES="$$SOURCES $$srcdir/src/video/mali-fbdev/*.c"' $(@D)/configure.ac; \
		python3 $(BR2_EXTERNAL_MINIME_PATH)/board/h700/patch_mali_dma_heap.py $(@D); \
	fi
endef
SDL2_POST_PATCH_HOOKS += SDL2_ADD_MALI_SOURCES
