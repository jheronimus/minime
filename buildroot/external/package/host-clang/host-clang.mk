################################################################################
#
# host-clang
#
################################################################################

HOST_CLANG_VERSION = 22
HOST_CLANG_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/host-clang
HOST_CLANG_SITE_METHOD = local
HOST_CLANG_SOURCE =
HOST_CLANG_LICENSE = Apache-2.0 with LLVM-exception
HOST_CLANG_LICENSE_FILES = README

HOST_CLANG_DEPENDENCIES = host-llvm
HOST_CLANG_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu
HOST_CLANG_LLVM_PREFIX = /usr/lib/llvm-$(HOST_CLANG_VERSION)

define HOST_CLANG_INSTALL_CMDS
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/clang-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang
	ln -sf /usr/bin/clang-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang-$(HOST_CLANG_VERSION)
	ln -sf /usr/bin/clang++-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang++
	ln -sf /usr/bin/clang-cpp-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang-cpp
	ln -sf /usr/bin/clang-tblgen-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang-tblgen

	$(INSTALL) -d $(HOST_DIR)/lib
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 $(HOST_DIR)/lib/libclang.so
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 $(HOST_DIR)/lib/libclang.so.1
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 $(HOST_DIR)/lib/libclang-$(HOST_CLANG_VERSION).so.$(HOST_CLANG_VERSION)
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_VERSION).1 $(HOST_DIR)/lib/libclang-cpp.so
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_VERSION).1 $(HOST_DIR)/lib/libclang-cpp.so.$(HOST_CLANG_VERSION).1

	$(INSTALL) -d $(HOST_DIR)/lib/cmake/clang
	cp -a $(HOST_CLANG_LLVM_PREFIX)/lib/cmake/clang/. $(HOST_DIR)/lib/cmake/clang/
endef

$(eval $(host-generic-package))

