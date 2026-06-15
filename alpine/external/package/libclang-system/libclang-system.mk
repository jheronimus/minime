################################################################################
#
# libclang-system
#
################################################################################

LIBCLANG_SYSTEM_VERSION = 19
LIBCLANG_SYSTEM_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/libclang-system
LIBCLANG_SYSTEM_SITE_METHOD = local
LIBCLANG_SYSTEM_SOURCE =
LIBCLANG_SYSTEM_LICENSE = Apache-2.0 with exceptions
LIBCLANG_SYSTEM_LICENSE_FILES = README

HOST_LIBCLANG_SYSTEM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

define HOST_LIBCLANG_SYSTEM_INSTALL_CMDS
	$(INSTALL) -d $(HOST_DIR)/lib
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-19.so.1 $(HOST_DIR)/lib/libclang.so
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-19.so.1 $(HOST_DIR)/lib/libclang.so.1
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-19.so.1 $(HOST_DIR)/lib/libclang-19.so.19
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-cpp.so.19.1 $(HOST_DIR)/lib/libclang-cpp.so
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libclang-cpp.so.19.1 $(HOST_DIR)/lib/libclang-cpp.so.19.1
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libLLVM.so.19.1 $(HOST_DIR)/lib/libLLVM.so
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libLLVM.so.19.1 $(HOST_DIR)/lib/libLLVM.so.19.1
	ln -sf $(HOST_LIBCLANG_SYSTEM_LIBDIR)/libLLVM-19.so $(HOST_DIR)/lib/libLLVM-19.so
endef

$(eval $(host-generic-package))
