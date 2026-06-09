################################################################################
#
# preloaded-roms
#
################################################################################

PRELOADED_ROMS_VERSION = 413e0c74465a03ece75a86d7957ff4a84afcab61
PRELOADED_ROMS_SITE = https://github.com/minime-os/roms.git
PRELOADED_ROMS_SITE_METHOD = git
PRELOADED_ROMS_LICENSE = Free / Shareware

# Option A: Stage ROMs directly to the binaries UI directory so they are picked up by post-image.sh
PRELOADED_ROMS_TARGET_ROMS_DIR = $(BINARIES_DIR)/ui/roms

define PRELOADED_ROMS_INSTALL_TARGET_CMDS
	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)"
	
	# Copy console ROM folders if they are selected in Buildroot
	if [ "$(BR2_PACKAGE_LIBRETRO_FCEUMM)" = "y" ] && [ -d "$(@D)/Roms/Nintendo Entertainment System (FC)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/nes"; \
		cp -a "$(@D)/Roms/Nintendo Entertainment System (FC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/nes/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_GAMBATTE)" = "y" ]; then \
		if [ -d "$(@D)/Roms/Game Boy (GB)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb"; \
			cp -a "$(@D)/Roms/Game Boy (GB)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb/"; \
		fi; \
		if [ -d "$(@D)/Roms/Game Boy Color (GBC)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb"; \
			cp -a "$(@D)/Roms/Game Boy Color (GBC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gb/"; \
		fi; \
	fi
	if { [ "$(BR2_PACKAGE_LIBRETRO_GPSP)" = "y" ] || [ "$(BR2_PACKAGE_LIBRETRO_MGBA)" = "y" ]; } && [ -d "$(@D)/Roms/Game Boy Advance (GBA)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba"; \
		cp -a "$(@D)/Roms/Game Boy Advance (GBA)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_PICODRIVE)" = "y" ]; then \
		if [ -d "$(@D)/Roms/Sega Genesis (MD)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/md"; \
			cp -a "$(@D)/Roms/Sega Genesis (MD)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/md/"; \
		fi; \
		if [ -d "$(@D)/Roms/Sega Game Gear (GG)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gg"; \
			cp -a "$(@D)/Roms/Sega Game Gear (GG)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gg/"; \
		fi; \
		if [ -d "$(@D)/Roms/Sega Master System (SMS)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/sms"; \
			cp -a "$(@D)/Roms/Sega Master System (SMS)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/sms/"; \
		fi; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_PCSX_REARMED)" = "y" ] && [ -d "$(@D)/Roms/Sony PlayStation (PS)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx"; \
		cp -a "$(@D)/Roms/Sony PlayStation (PS)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_PCE_FAST)" = "y" ] && [ -d "$(@D)/Roms/TurboGrafx-16 (PCE)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pce"; \
		cp -a "$(@D)/Roms/TurboGrafx-16 (PCE)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pce/"; \
	fi
	if { [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_SUPAFAUST)" = "y" ] || [ "$(BR2_PACKAGE_LIBRETRO_SNES9X2005_PLUS)" = "y" ]; } && [ -d "$(@D)/Roms/Super Nintendo Entertainment System (SFC)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes"; \
		cp -a "$(@D)/Roms/Super Nintendo Entertainment System (SFC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes/"; \
	fi
	# Commented out systems (no emulators shipped yet):
	# if [ "$(BR2_PACKAGE_LIBRETRO_RACE)" = "y" ]; then \
	# 	if [ -d "$(@D)/Roms/Neo Geo Pocket (NGP)" ]; then \
	# 		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp"; \
	# 		cp -a "$(@D)/Roms/Neo Geo Pocket (NGP)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp/"; \
	# 	fi; \
	# 	if [ -d "$(@D)/Roms/Neo Geo Pocket Color (NGPC)" ]; then \
	# 		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp"; \
	# 		cp -a "$(@D)/Roms/Neo Geo Pocket Color (NGPC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp/"; \
	# 	fi; \
	# fi
	# if [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_VB)" = "y" ] && [ -d "$(@D)/Roms/Virtual Boy (VB)" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/vb"; \
	# 	cp -a "$(@D)/Roms/Virtual Boy (VB)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/vb/"; \
	# 	fi
	# if [ "$(BR2_PACKAGE_LIBRETRO_POKEMINI)" = "y" ] && [ -d "$(@D)/Roms/Pokemon mini (PKM)" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pkm"; \
	# 	cp -a "$(@D)/Roms/Pokemon mini (PKM)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pkm/"; \
	# fi
	# if [ "$(BR2_PACKAGE_LIBRETRO_FAKE08)" = "y" ] && [ -d "$(@D)/Roms/Pico-8 (P8)" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pico8"; \
	# 	cp -a "$(@D)/Roms/Pico-8 (P8)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pico8/"; \
	# fi
	# if [ -d "$(@D)/Roms/Atari Lynx" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/lynx"; \
	# 	cp -a "$(@D)/Roms/Atari Lynx/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/lynx/"; \
	# fi
	# if [ -d "$(@D)/Roms/Wonderswan" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/wswan"; \
	# 	cp -a "$(@D)/Roms/Wonderswan/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/wswan/"; \
	# fi
	# if [ -d "$(@D)/Roms/Mega Duck" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/mduck"; \
	# 	cp -a "$(@D)/Roms/Mega Duck/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/mduck/"; \
	# fi
	# if [ -d "$(@D)/Roms/Watara Supervision" ]; then \
	# 	mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/watara"; \
	# 	cp -a "$(@D)/Roms/Watara Supervision/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/watara/"; \
	# fi
endef

$(eval $(generic-package))
