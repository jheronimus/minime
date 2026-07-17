include $(sort $(wildcard $(BR2_EXTERNAL_MINIME_PATH)/package/*/*.mk))

# Hooks to copy custom DTS files and patch base DTS file in Linux kernel
define MINIME_COPY_DTS
	if [ -d $(BR2_EXTERNAL_MINIME_PATH)/../alpine/board/h700/dts ]; then \
		cp $(BR2_EXTERNAL_MINIME_PATH)/../alpine/board/h700/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/allwinner/; \
	fi
	if [ -d $(BR2_EXTERNAL_MINIME_PATH)/../alpine/board/rk3326/dts ]; then \
		cp $(BR2_EXTERNAL_MINIME_PATH)/../alpine/board/rk3326/dts/*.dts \
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

# Minime uses libmali for GLES on the Buildroot branch. Keep SDL's legacy
# proprietary Mali/fbdev backend disabled.
SDL2_CONF_OPTS += --disable-video-mali
