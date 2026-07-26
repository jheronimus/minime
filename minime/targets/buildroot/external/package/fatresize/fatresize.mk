################################################################################
#
# fatresize
#
################################################################################

FATRESIZE_VERSION = 1.1.0
FATRESIZE_SOURCE = fatresize_$(FATRESIZE_VERSION).orig.tar.gz
FATRESIZE_SITE = https://deb.debian.org/debian/pool/main/f/fatresize
FATRESIZE_DEPENDENCIES = host-patchelf host-pkgconf parted
FATRESIZE_LICENSE = GPL-3.0+
FATRESIZE_LICENSE_FILES = COPYING

$(eval $(autotools-package))
