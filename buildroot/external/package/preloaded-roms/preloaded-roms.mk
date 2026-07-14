################################################################################
#
# preloaded-roms
#
################################################################################

PRELOADED_ROMS_VERSION = local
PRELOADED_ROMS_SITE = $(BR2_EXTERNAL)/../../roms
PRELOADED_ROMS_SITE_METHOD = local
PRELOADED_ROMS_LICENSE = Free / Shareware

# Option A: Stage ROMs directly to the binaries UI directory so they are picked up by post-image.sh
PRELOADED_ROMS_TARGET_ROMS_DIR = $(BINARIES_DIR)/ui/roms

define PRELOADED_ROMS_INSTALL_TARGET_CMDS
	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)"
	
	# Copy console ROM folders if they exist in the repository
	if [ -d "$(@D)/nes" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/nes"; \
		cp -a "$(@D)/nes/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/nes/"; \
	fi
	if [ -d "$(@D)/gb" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb"; \
		cp -a "$(@D)/gb/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb/"; \
	fi
	if [ -d "$(@D)/gba" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba"; \
		cp -a "$(@D)/gba/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba/"; \
	fi
	if [ -d "$(@D)/md" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/md"; \
		cp -a "$(@D)/md/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/md/"; \
	fi
	if [ -d "$(@D)/gg" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gg"; \
		cp -a "$(@D)/gg/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gg/"; \
	fi
	if [ -d "$(@D)/sms" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/sms"; \
		cp -a "$(@D)/sms/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/sms/"; \
	fi
	if [ -d "$(@D)/psx" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx"; \
		cp -a "$(@D)/psx/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx/"; \
	fi
	if [ -d "$(@D)/pce" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pce"; \
		cp -a "$(@D)/pce/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pce/"; \
	fi
	if [ -d "$(@D)/snes" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes"; \
		cp -a "$(@D)/snes/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes/"; \
	fi
	if [ -d "$(@D)/ss" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ss"; \
		cp -a "$(@D)/ss/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ss/"; \
	fi
	if [ -d "$(@D)/arc" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/arc"; \
		cp -a "$(@D)/arc/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/arc/"; \
	fi
	if [ -d "$(@D)/lynx" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/lynx"; \
		cp -a "$(@D)/lynx/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/lynx/"; \
	fi
	if [ -d "$(@D)/ngp" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp"; \
		cp -a "$(@D)/ngp/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp/"; \
	fi
	if [ -d "$(@D)/wswan" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/wswan"; \
		cp -a "$(@D)/wswan/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/wswan/"; \
	fi
endef

$(eval $(generic-package))
