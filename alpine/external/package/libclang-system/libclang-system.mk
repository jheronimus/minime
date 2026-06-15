################################################################################
#
# libclang-system
#
################################################################################

LIBCLANG_SYSTEM_VERSION = 22
LIBCLANG_SYSTEM_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/libclang-system
LIBCLANG_SYSTEM_SITE_METHOD = local
LIBCLANG_SYSTEM_SOURCE =
LIBCLANG_SYSTEM_LICENSE = Apache-2.0 with LLVM-exception
LIBCLANG_SYSTEM_LICENSE_FILES = README

HOST_LIBCLANG_SYSTEM_DEPENDENCIES = host-llvm-system
HOST_LIBCLANG_SYSTEM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

define HOST_LIBCLANG_SYSTEM_INSTALL_CMDS
	$(INSTALL) -d $(HOST_DIR)/lib
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-$(LIBCLANG_SYSTEM_VERSION).so.1 $(HOST_DIR)/lib/libclang.so
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-$(LIBCLANG_SYSTEM_VERSION).so.1 $(HOST_DIR)/lib/libclang.so.1
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-$(LIBCLANG_SYSTEM_VERSION).so.1 $(HOST_DIR)/lib/libclang-$(LIBCLANG_SYSTEM_VERSION).so.$(LIBCLANG_SYSTEM_VERSION)
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-cpp.so.$(LIBCLANG_SYSTEM_VERSION).1 $(HOST_DIR)/lib/libclang-cpp.so
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-cpp.so.$(LIBCLANG_SYSTEM_VERSION).1 $(HOST_DIR)/lib/libclang-cpp.so.$(LIBCLANG_SYSTEM_VERSION).1
endef

$(eval $(host-generic-package))
