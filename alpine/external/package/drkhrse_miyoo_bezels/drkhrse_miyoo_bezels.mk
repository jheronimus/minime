################################################################################
#
# drkhrse_miyoo_bezels
#
################################################################################

DRKHRSE_MIYOO_BEZELS_VERSION = master
DRKHRSE_MIYOO_BEZELS_SITE = https://github.com/drkhrse/drkhrse_miyoo_bezels.git
DRKHRSE_MIYOO_BEZELS_SITE_METHOD = git
DRKHRSE_MIYOO_BEZELS_LICENSE = GPL-3.0
DRKHRSE_MIYOO_BEZELS_LICENSE_FILES = LICENSE

DRKHRSE_MIYOO_BEZELS_INSTALL_IMAGES = YES

define DRKHRSE_MIYOO_BEZELS_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/bezels
	# Copy bezel assets to the staging ui directory
	cp -rf $(@D)/* $(BINARIES_DIR)/ui/bezels/
endef

$(eval $(generic-package))
