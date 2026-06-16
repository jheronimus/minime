################################################################################
#
# host-llvm-system
#
################################################################################

# Provide the Buildroot host LLVM installation by symlinking/copying files
# from the Debian build container's apt.llvm.org LLVM/Clang toolchain.
# This avoids compiling host-llvm from source.

HOST_LLVM_SYSTEM_VERSION = 22
HOST_LLVM_SYSTEM_LLVM_PREFIX = /usr/lib/llvm-$(HOST_LLVM_SYSTEM_VERSION)
HOST_LLVM_SYSTEM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

# No source to download; files come from the container image.
HOST_LLVM_SYSTEM_SOURCE =
HOST_LLVM_SYSTEM_SITE =

define HOST_LLVM_SYSTEM_INSTALL_CMDS
	# LLVM tools used by other packages and the target LLVM build.
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/llvm-config-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-config
	ln -sf /usr/bin/llvm-tblgen-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-tblgen
	ln -sf /usr/bin/llvm-dis-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-dis
	ln -sf /usr/bin/llvm-link-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-link
	ln -sf /usr/bin/llvm-as-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-as
	ln -sf /usr/bin/llvm-ar-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-ar
	ln -sf /usr/bin/llvm-nm-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-nm
	ln -sf /usr/bin/llvm-objcopy-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-objcopy
	ln -sf /usr/bin/llvm-objdump-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-objdump
	ln -sf /usr/bin/llvm-profdata-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-profdata
	ln -sf /usr/bin/llvm-symbolizer-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llvm-symbolizer
	ln -sf /usr/bin/opt-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/opt
	ln -sf /usr/bin/llc-$(HOST_LLVM_SYSTEM_VERSION) $(HOST_DIR)/bin/llc

	# LLVM libraries expected by llvm-config / CMake exports.
	$(INSTALL) -d $(HOST_DIR)/lib
	$(RM) -f $(HOST_DIR)/lib/libLLVM*.so* \
		$(HOST_DIR)/lib/libLTO*.so* \
		$(HOST_DIR)/lib/libRemarks*.so*
	ln -sf $(HOST_LLVM_SYSTEM_LIBDIR)/libLLVM-$(HOST_LLVM_SYSTEM_VERSION).so \
		$(HOST_DIR)/lib/libLLVM-$(HOST_LLVM_SYSTEM_VERSION).so
	ln -sf $(HOST_LLVM_SYSTEM_LIBDIR)/libLLVM.so.$(HOST_LLVM_SYSTEM_VERSION).1 \
		$(HOST_DIR)/lib/libLLVM.so
	ln -sf $(HOST_LLVM_SYSTEM_LIBDIR)/libLLVM.so.$(HOST_LLVM_SYSTEM_VERSION).1 \
		$(HOST_DIR)/lib/libLLVM.so.$(HOST_LLVM_SYSTEM_VERSION).1
	ln -sf $(HOST_LLVM_SYSTEM_LIBDIR)/libLLVM.so.$(HOST_LLVM_SYSTEM_VERSION) \
		$(HOST_DIR)/lib/libLLVM.so.$(HOST_LLVM_SYSTEM_VERSION)
	for f in $(HOST_LLVM_SYSTEM_LLVM_PREFIX)/lib/*.so* \
		$(HOST_LLVM_SYSTEM_LLVM_PREFIX)/lib/*.a; do \
		[ -e "$$f" ] || continue; \
		target=$(HOST_DIR)/lib/$$(basename "$$f"); \
		$(RM) -rf "$$target"; \
		ln -sf "$$f" "$$target"; \
	done

	# LLVM headers (llvm/, llvm-c/, etc.).
	$(INSTALL) -d $(HOST_DIR)/include
	for d in $(HOST_LLVM_SYSTEM_LLVM_PREFIX)/include/*/; do \
		[ -d "$$d" ] || continue; \
		target=$(HOST_DIR)/include/$$(basename "$$d"); \
		$(RM) -rf "$$target"; \
		ln -sfn "$$d" "$$target"; \
	done

	# LLVM CMake configs consumed by spirv-llvm-translator, mesa3d, etc.
	$(RM) -rf $(HOST_DIR)/lib/cmake/llvm
	$(INSTALL) -d $(HOST_DIR)/lib/cmake/llvm
	cp -a $(HOST_LLVM_SYSTEM_LLVM_PREFIX)/lib/cmake/llvm/. \
		$(HOST_DIR)/lib/cmake/llvm/

	# libclc data files used by Mesa's OpenCL C compiler.
	$(RM) -rf $(HOST_DIR)/share/libclc
	$(INSTALL) -d $(HOST_DIR)/share/libclc
	cp -a $(HOST_LLVM_SYSTEM_LLVM_PREFIX)/share/libclc/. \
		$(HOST_DIR)/share/libclc/

	# llvm-config must also be visible from staging for target consumers.
	ln -sf $(HOST_DIR)/bin/llvm-config $(STAGING_DIR)/usr/bin/llvm-config
endef

$(eval $(host-generic-package))
