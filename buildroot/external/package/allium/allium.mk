################################################################################
#
# allium
#
################################################################################

ALLIUM_VERSION = v20260720
ALLIUM_DATE = $(ALLIUM_VERSION:v%=%)
ALLIUM_SITE = https://github.com/jheronimus/Allium/releases/download/$(ALLIUM_VERSION)
ALLIUM_SOURCE = allium-minime-aarch64.zip
ALLIUM_SITE_METHOD = wget
ALLIUM_LICENSE = MIT
ALLIUM_LICENSE_FILES = LICENSE

ALLIUM_DEPENDENCIES =
ALLIUM_INSTALL_IMAGES = YES

define ALLIUM_EXTRACT_CMDS
	cd $(@D) && unzip -o $(DL_DIR)/allium/$(ALLIUM_SOURCE)
endef

define ALLIUM_INSTALL_IMAGES_CMDS
	# Stage Allium to SD card root (.ui/ for Allium internals, apps/ for paks)
	mkdir -p $(BINARIES_DIR)/ui/.ui
	cp -a $(@D)/.ui/. $(BINARIES_DIR)/ui/.ui/

	if [ -d $(@D)/apps ]; then \
		mkdir -p $(BINARIES_DIR)/ui/apps; \
		cp -a $(@D)/apps/. $(BINARIES_DIR)/ui/apps/; \
	fi

	if [ -d $(@D)/.tmp_update ]; then \
		mkdir -p $(BINARIES_DIR)/ui/.tmp_update; \
		cp -a $(@D)/.tmp_update/. $(BINARIES_DIR)/ui/.tmp_update/; \
	fi

	if [ -d $(@D)/RetroArch ]; then \
		cp -a $(@D)/RetroArch $(BINARIES_DIR)/ui/; \
	fi
endef

$(eval $(generic-package))
