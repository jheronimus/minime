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
SYNCTHING_GO_ENV = GOPROXY=https://proxy.golang.org,direct

$(eval $(golang-package))
