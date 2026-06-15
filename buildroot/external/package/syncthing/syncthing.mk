################################################################################
#
# syncthing
#
################################################################################

SYNCTHING_VERSION = 2.1.1
SYNCTHING_SITE = $(call github,syncthing,syncthing,v$(SYNCTHING_VERSION))
SYNCTHING_LICENSE = MPL-2.0
SYNCTHING_LICENSE_FILES = LICENSE
SYNCTHING_GOMOD = github.com/syncthing/syncthing
SYNCTHING_BUILD_TARGETS = cmd/syncthing

define SYNCTHING_REMOVE_BROKEN_SQLITE_REPLACE
	sed -i '/calmh\/go-sqlite3/d' $(@D)/go.mod
endef
SYNCTHING_POST_PATCH_HOOKS += SYNCTHING_REMOVE_BROKEN_SQLITE_REPLACE

$(eval $(golang-package))
