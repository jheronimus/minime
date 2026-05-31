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

