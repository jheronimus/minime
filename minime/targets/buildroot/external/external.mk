MINIME_BOARD_NAME = $(notdir $(patsubst %/patches,%,$(qstrip $(BR2_GLOBAL_PATCH_DIR))))

include $(sort $(wildcard $(BR2_EXTERNAL_MINIME_PATH)/package/*/*.mk))

# Hooks to copy custom DTS files and patch base DTS file in Linux kernel
define MINIME_COPY_DTS
	if [ -d $(MINIME_ROOT)/boards/h700/dts ]; then \
		cp $(MINIME_ROOT)/boards/h700/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/allwinner/; \
	fi
	if [ -d $(MINIME_ROOT)/boards/rk3326/dts ]; then \
		cp $(MINIME_ROOT)/boards/rk3326/dts/*.dts \
			$(LINUX_DIR)/arch/arm64/boot/dts/rockchip/; \
		echo "dtb-\$$(CONFIG_ARCH_ROCKCHIP) += rk3326-anbernic-rg351p.dtb" >> $(LINUX_DIR)/arch/arm64/boot/dts/rockchip/Makefile; \
		echo "dtb-\$$(CONFIG_ARCH_ROCKCHIP) += rk3326-anbernic-rg351mp.dtb" >> $(LINUX_DIR)/arch/arm64/boot/dts/rockchip/Makefile; \
	fi
endef
LINUX_PRE_PATCH_HOOKS += MINIME_COPY_DTS


define MINIME_PATCH_LINUX_CONFIG
	mkdir -p $(LINUX_DIR)/minime-firmware
	cp -rL $(MINIME_ROOT)/boards/common/firmware/* $(LINUX_DIR)/minime-firmware/
	if [ -d $(MINIME_ROOT)/boards/$(MINIME_BOARD_NAME)/firmware ]; then \
		cp -rL $(MINIME_ROOT)/boards/$(MINIME_BOARD_NAME)/firmware/* $(LINUX_DIR)/minime-firmware/; \
	fi
	sed -i 's|__MINIME_BOARD_FIRMWARE_DIR__|$(LINUX_DIR)/minime-firmware|g' $(LINUX_DIR)/.config
	sed -i 's|__MINIME_COMMON_FIRMWARE_DIR__|$(MINIME_ROOT)/boards/common/firmware|g' $(LINUX_DIR)/.config
endef
LINUX_POST_CONFIGURE_HOOKS += MINIME_PATCH_LINUX_CONFIG

# Minime uses libmali for GLES on the Buildroot branch. Keep SDL's legacy
# proprietary Mali/fbdev backend disabled.
SDL2_CONF_OPTS += --disable-video-mali
