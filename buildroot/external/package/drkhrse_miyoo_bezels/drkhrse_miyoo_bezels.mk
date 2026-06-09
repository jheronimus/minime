################################################################################
#
# drkhrse_miyoo_bezels
#
################################################################################

DRKHRSE_MIYOO_BEZELS_VERSION = main
DRKHRSE_MIYOO_BEZELS_SITE = https://github.com/drkhrse/drkhrse_miyoo_bezels.git
DRKHRSE_MIYOO_BEZELS_SITE_METHOD = git
DRKHRSE_MIYOO_BEZELS_LICENSE = GPL-3.0
DRKHRSE_MIYOO_BEZELS_LICENSE_FILES = LICENSE

DRKHRSE_MIYOO_BEZELS_INSTALL_IMAGES = YES

define DRKHRSE_MIYOO_BEZELS_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/bezels

	# Game Boy Classic, Pocket, and Color bezels in subfolders under gb/
	if [ -d "$(@D)/drkhrse_miyoo_bezels/DMG" ]; then \
		mkdir -p $(BINARIES_DIR)/ui/bezels/gb/dmg; \
		cp -rf $(@D)/drkhrse_miyoo_bezels/DMG/* $(BINARIES_DIR)/ui/bezels/gb/dmg/; \
	fi
	if [ -d "$(@D)/drkhrse_miyoo_bezels/GBP" ]; then \
		mkdir -p $(BINARIES_DIR)/ui/bezels/gb/gbp; \
		cp -rf $(@D)/drkhrse_miyoo_bezels/GBP/* $(BINARIES_DIR)/ui/bezels/gb/gbp/; \
	fi
	if [ -d "$(@D)/drkhrse_miyoo_bezels/GBC" ]; then \
		mkdir -p $(BINARIES_DIR)/ui/bezels/gb/gbc; \
		cp -rf $(@D)/drkhrse_miyoo_bezels/GBC/* $(BINARIES_DIR)/ui/bezels/gb/gbc/; \
	fi

	# Game Boy Advance bezels in gba/
	if [ -d "$(@D)/drkhrse_miyoo_bezels/GBA" ]; then \
		mkdir -p $(BINARIES_DIR)/ui/bezels/gba; \
		cp -rf $(@D)/drkhrse_miyoo_bezels/GBA/* $(BINARIES_DIR)/ui/bezels/gba/; \
	fi

	# Game Gear bezels in gg/
	if [ -d "$(@D)/drkhrse_miyoo_bezels/GG" ]; then \
		mkdir -p $(BINARIES_DIR)/ui/bezels/gg; \
		cp -rf $(@D)/drkhrse_miyoo_bezels/GG/* $(BINARIES_DIR)/ui/bezels/gg/; \
	fi

	# Commented out system bezels (no emulators shipped yet):
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/NGP" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/ngp; \
	# 	cp -rf $(@D)/drkhrse_miyoo_bezels/NGP/* $(BINARIES_DIR)/ui/bezels/ngp/; \
	# fi
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/NGPC" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/ngp; \
	# 	cp -rf $(@D)/drkhrse_miyoo_bezels/NGPC/* $(BINARIES_DIR)/ui/bezels/ngp/; \
	# fi
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/WS" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/wswan; \
	# 	cp -rf $(@D)/drkhrse_miyoo_bezels/WS/* $(BINARIES_DIR)/ui/bezels/wswan/; \
	# fi
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/WSC" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/wswan; \
	# 	cp -rf $(@D)/drkhrse_miyoo_bezels/WSC/* $(BINARIES_DIR)/ui/bezels/wswan/; \
	# fi
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/Mega Duck" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/mduck; \
	# 	cp -rf "$(@D)/drkhrse_miyoo_bezels/Mega Duck/." $(BINARIES_DIR)/ui/bezels/mduck/; \
	# fi
	# if [ -d "$(@D)/drkhrse_miyoo_bezels/Watara Supervision" ]; then \
	# 	mkdir -p $(BINARIES_DIR)/ui/bezels/watara; \
	# 	cp -rf "$(@D)/drkhrse_miyoo_bezels/Watara Supervision/." $(BINARIES_DIR)/ui/bezels/watara/; \
	# fi
endef

$(eval $(generic-package))
