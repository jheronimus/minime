################################################################################
#
# host-clang-system
#
################################################################################

# Provide the Buildroot host Clang installation by symlinking files from the
# Debian build container's apt.llvm.org Clang toolchain.
# This avoids compiling host-clang from source.

HOST_CLANG_SYSTEM_VERSION = 22
HOST_CLANG_SYSTEM_LLVM_PREFIX = /usr/lib/llvm-$(HOST_CLANG_SYSTEM_VERSION)
HOST_CLANG_SYSTEM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

# No source to download; files come from the container image.
HOST_CLANG_SYSTEM_SOURCE =
HOST_CLANG_SYSTEM_SITE =

define HOST_CLANG_SYSTEM_INSTALL_CMDS
	# Clang tools used by other packages and the target build.
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/clang-$(HOST_CLANG_SYSTEM_VERSION) $(HOST_DIR)/bin/clang
	ln -sf /usr/bin/clang-$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/bin/clang-$(HOST_CLANG_SYSTEM_VERSION)
	ln -sf /usr/bin/clang++-$(HOST_CLANG_SYSTEM_VERSION) $(HOST_DIR)/bin/clang++
	ln -sf /usr/bin/clang-cpp-$(HOST_CLANG_SYSTEM_VERSION) $(HOST_DIR)/bin/clang-cpp
	ln -sf /usr/bin/clang-tblgen-$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/bin/clang-tblgen
	ln -sf /usr/bin/clang-format-$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/bin/clang-format
	ln -sf /usr/bin/clang-offload-bundler-$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/bin/clang-offload-bundler
	ln -sf /usr/bin/clang-offload-packager-$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/bin/clang-offload-packager

	# Clang libraries expected by CMake exports and libclc.
	$(INSTALL) -d $(HOST_DIR)/lib
	$(RM) -f $(HOST_DIR)/lib/libclang*.so* $(HOST_DIR)/lib/libclang*.a
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-$(HOST_CLANG_SYSTEM_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang.so
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-$(HOST_CLANG_SYSTEM_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang.so.1
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-$(HOST_CLANG_SYSTEM_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang-$(HOST_CLANG_SYSTEM_VERSION).so.$(HOST_CLANG_SYSTEM_VERSION)
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_SYSTEM_VERSION).1 \
		$(HOST_DIR)/lib/libclang-cpp.so
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_SYSTEM_VERSION).1 \
		$(HOST_DIR)/lib/libclang-cpp.so.$(HOST_CLANG_SYSTEM_VERSION).1
	ln -sf $(HOST_CLANG_SYSTEM_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_SYSTEM_VERSION) \
		$(HOST_DIR)/lib/libclang-cpp.so.$(HOST_CLANG_SYSTEM_VERSION)
	for f in $(HOST_CLANG_SYSTEM_LLVM_PREFIX)/lib/libclang*.a \
		$(HOST_CLANG_SYSTEM_LIBDIR)/libclang*.so*; do \
		[ -e "$$f" ] || continue; \
		target=$(HOST_DIR)/lib/$$(basename "$$f"); \
		$(RM) -rf "$$target"; \
		ln -sf "$$f" "$$target"; \
	done

	# Clang CMake configs.
	$(RM) -rf $(HOST_DIR)/lib/cmake/clang
	$(INSTALL) -d $(HOST_DIR)/lib/cmake/clang
	cp -a $(HOST_CLANG_SYSTEM_LLVM_PREFIX)/lib/cmake/clang/. \
		$(HOST_DIR)/lib/cmake/clang/

	# Clang builtin headers used by the compiler runtime.
	$(RM) -rf $(HOST_DIR)/lib/clang/$(HOST_CLANG_SYSTEM_VERSION)/include
	$(INSTALL) -d $(HOST_DIR)/lib/clang/$(HOST_CLANG_SYSTEM_VERSION)
	ln -sfn $(HOST_CLANG_SYSTEM_LLVM_PREFIX)/lib/clang/$(HOST_CLANG_SYSTEM_VERSION)/include \
		$(HOST_DIR)/lib/clang/$(HOST_CLANG_SYSTEM_VERSION)/include

	# Clang support files.
	$(RM) -rf $(HOST_DIR)/share/clang
	ln -sfn $(HOST_CLANG_SYSTEM_LLVM_PREFIX)/share/clang $(HOST_DIR)/share/clang
endef

$(eval $(host-generic-package))
