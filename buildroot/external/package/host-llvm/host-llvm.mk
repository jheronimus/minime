################################################################################
#
# host-llvm
#
################################################################################

HOST_LLVM_VERSION = 22
HOST_LLVM_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/host-llvm
HOST_LLVM_SITE_METHOD = local
HOST_LLVM_SOURCE =
HOST_LLVM_LICENSE = Apache-2.0 with LLVM-exception
HOST_LLVM_LICENSE_FILES = README

HOST_LLVM_PROVIDES = host-libclc

HOST_LLVM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu
HOST_LLVM_LLVM_PREFIX = /usr/lib/llvm-$(HOST_LLVM_VERSION)
HOST_LLVM_LIBCLC_DIR = $(HOST_LLVM_LLVM_PREFIX)/share/libclc

define HOST_LLVM_INSTALL_CMDS
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/llvm-config-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-config
	ln -sf /usr/bin/llvm-tblgen-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-tblgen
	ln -sf /usr/bin/llvm-dis-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-dis

	$(INSTALL) -d $(HOST_DIR)/lib
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM.so.$(HOST_LLVM_VERSION).1 $(HOST_DIR)/lib/libLLVM.so
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM.so.$(HOST_LLVM_VERSION).1 $(HOST_DIR)/lib/libLLVM.so.$(HOST_LLVM_VERSION).1

	$(INSTALL) -d $(HOST_DIR)/lib/cmake/llvm
	cp -a $(HOST_LLVM_LLVM_PREFIX)/lib/cmake/llvm/. $(HOST_DIR)/lib/cmake/llvm/

	$(INSTALL) -d $(HOST_DIR)/share/libclc
	cp -a $(HOST_LLVM_LIBCLC_DIR)/. $(HOST_DIR)/share/libclc/

	$(INSTALL) -d $(STAGING_DIR)/usr/bin
	ln -sf $(HOST_DIR)/bin/llvm-config $(STAGING_DIR)/usr/bin/llvm-config
endef

$(eval $(call inner-generic-package,host-llvm,HOST_LLVM,LLVM,host))


