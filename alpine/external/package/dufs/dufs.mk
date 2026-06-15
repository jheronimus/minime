################################################################################
#
# dufs
#
################################################################################

DUFS_VERSION = 0.46.0
DUFS_SITE = $(call github,sigoden,dufs,v$(DUFS_VERSION))
DUFS_LICENSE = MIT OR Apache-2.0
DUFS_LICENSE_FILES = LICENSE-MIT LICENSE-APACHE

$(eval $(cargo-package))
