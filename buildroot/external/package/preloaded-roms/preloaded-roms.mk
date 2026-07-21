################################################################################
#
# preloaded-roms
#
################################################################################

PRELOADED_ROMS_VERSION = local
PRELOADED_ROMS_SITE = $(BR2_EXTERNAL)/../../roms
PRELOADED_ROMS_SITE_METHOD = local
PRELOADED_ROMS_LICENSE = Free / Shareware

define PRELOADED_ROMS_INSTALL_TARGET_CMDS
	sh $(PRELOADED_ROMS_SITE)/install.sh $(BINARIES_DIR)/ui
endef

$(eval $(generic-package))
