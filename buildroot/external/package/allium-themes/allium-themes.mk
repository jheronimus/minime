################################################################################
#
# allium-themes
#
################################################################################

ALLIUM_THEMES_VERSION = a77abc867d6f4e836b186e34944b9b862b8ed3dd
ALLIUM_THEMES_SITE = $(call github,goweiwen,Allium-Themes,$(ALLIUM_THEMES_VERSION))
ALLIUM_THEMES_LICENSE = See upstream
ALLIUM_THEMES_LICENSE_FILES = LICENSE
ALLIUM_THEMES_INSTALL_IMAGES = YES

define ALLIUM_THEMES_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.ui/themes
	cp -a $(@D)/Themes/. $(BINARIES_DIR)/ui/.ui/themes/
endef

$(eval $(generic-package))
