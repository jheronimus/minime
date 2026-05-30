################################################################################
#
# preloaded-roms
#
################################################################################

PRELOADED_ROMS_VERSION = fbcfac838358516cf93f96a142be0c1036046c23
PRELOADED_ROMS_SITE = https://github.com/jheronimus/preloaded-roms.git
PRELOADED_ROMS_SITE_METHOD = git
PRELOADED_ROMS_LICENSE = Free / Shareware

# Option A: Stage ROMs directly to the binaries UI directory so they are picked up by post-image.sh
PRELOADED_ROMS_TARGET_ROMS_DIR = $(BINARIES_DIR)/ui/Roms

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
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gbc"; \
			cp -a "$(@D)/Roms/Game Boy Color (GBC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gbc/"; \
		fi; \
	fi
	if { [ "$(BR2_PACKAGE_LIBRETRO_GPSP)" = "y" ] || [ "$(BR2_PACKAGE_LIBRETRO_MGBA)" = "y" ]; } && [ -d "$(@D)/Roms/Game Boy Advance (GBA)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba"; \
		cp -a "$(@D)/Roms/Game Boy Advance (GBA)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gba/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_PICODRIVE)" = "y" ]; then \
		if [ -d "$(@D)/Roms/Sega Genesis (MD)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/genesis"; \
			cp -a "$(@D)/Roms/Sega Genesis (MD)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/genesis/"; \
		fi; \
		if [ -d "$(@D)/Roms/Sega Game Gear (GG)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gamegear"; \
			cp -a "$(@D)/Roms/Sega Game Gear (GG)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/gamegear/"; \
		fi; \
		if [ -d "$(@D)/Roms/Sega Master System (SMS)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/mastersystem"; \
			cp -a "$(@D)/Roms/Sega Master System (SMS)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/mastersystem/"; \
		fi; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_PCSX_REARMED)" = "y" ] && [ -d "$(@D)/Roms/Sony PlayStation (PS)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx"; \
		cp -a "$(@D)/Roms/Sony PlayStation (PS)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/psx/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_PCE_FAST)" = "y" ] && [ -d "$(@D)/Roms/TurboGrafx-16 (PCE)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/tg16"; \
		cp -a "$(@D)/Roms/TurboGrafx-16 (PCE)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/tg16/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_RACE)" = "y" ]; then \
		if [ -d "$(@D)/Roms/Neo Geo Pocket (NGP)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp"; \
			cp -a "$(@D)/Roms/Neo Geo Pocket (NGP)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngp/"; \
		fi; \
		if [ -d "$(@D)/Roms/Neo Geo Pocket Color (NGPC)" ]; then \
			mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngpc"; \
			cp -a "$(@D)/Roms/Neo Geo Pocket Color (NGPC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/ngpc/"; \
		fi; \
	fi
	if { [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_SUPAFAUST)" = "y" ] || [ "$(BR2_PACKAGE_LIBRETRO_SNES9X2005_PLUS)" = "y" ]; } && [ -d "$(@D)/Roms/Super Nintendo Entertainment System (SFC)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes"; \
		cp -a "$(@D)/Roms/Super Nintendo Entertainment System (SFC)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/snes/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_MEDNAFEN_VB)" = "y" ] && [ -d "$(@D)/Roms/Virtual Boy (VB)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/virtualboy"; \
		cp -a "$(@D)/Roms/Virtual Boy (VB)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/virtualboy/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_POKEMINI)" = "y" ] && [ -d "$(@D)/Roms/Pokemon mini (PKM)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pokemini"; \
		cp -a "$(@D)/Roms/Pokemon mini (PKM)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pokemini/"; \
	fi
	if [ "$(BR2_PACKAGE_LIBRETRO_FAKE08)" = "y" ] && [ -d "$(@D)/Roms/Pico-8 (P8)" ]; then \
		mkdir -p "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pico8"; \
		cp -a "$(@D)/Roms/Pico-8 (P8)/." "$(PRELOADED_ROMS_TARGET_ROMS_DIR)/pico8/"; \
	fi
endef

$(eval $(generic-package))
