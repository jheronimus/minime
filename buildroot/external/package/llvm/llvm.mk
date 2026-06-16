################################################################################
#
# llvm (system/host override definitions)
#
################################################################################

ifeq ($(BR2_PACKAGE_HOST_LLVM_SYSTEM),y)

# 1. Target LLVM/Clang Override
# Prevent compiling LLVM/Clang for target from source by making them dummy packages
LLVM_SOURCE =
LLVM_SITE =
LLVM_CONFIGURE_CMDS =
LLVM_BUILD_CMDS =
LLVM_INSTALL_STAGING_CMDS =
LLVM_INSTALL_TARGET_CMDS =

CLANG_SOURCE =
CLANG_SITE =
CLANG_CONFIGURE_CMDS =
CLANG_BUILD_CMDS =
CLANG_INSTALL_STAGING_CMDS =
CLANG_INSTALL_TARGET_CMDS =

# 2. Mesa3D Override
# Force Mesa3D to disable target LLVM compile support
MESA3D_CONF_OPTS := $(subst -Dllvm=enabled,-Dllvm=disabled,$(MESA3D_CONF_OPTS))

# Configure Mesa3D to use host/system compilers for Panfrost
MESA3D_CONF_OPTS += -Dmesa-clc=system -Dprecomp-compiler=system

# Add host-mesa3d dependency to target mesa3d configure target
mesa3d-configure: host-mesa3d

# 3. Host LLVM Override
HOST_LLVM_VERSION = 22
HOST_LLVM_PREFIX = /usr/lib/llvm-$(HOST_LLVM_VERSION)
HOST_LLVM_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

HOST_LLVM_SOURCE =
HOST_LLVM_SITE =
HOST_LLVM_DEPENDENCIES =
HOST_LLVM_POST_INSTALL_HOOKS =

HOST_LLVM_CONFIGURE_CMDS =
HOST_LLVM_BUILD_CMDS =
define HOST_LLVM_INSTALL_CMDS
	# LLVM tools used by other packages and the target LLVM build.
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/llvm-config-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-config
	ln -sf /usr/bin/llvm-tblgen-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-tblgen
	ln -sf /usr/bin/llvm-dis-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-dis
	ln -sf /usr/bin/llvm-link-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-link
	ln -sf /usr/bin/llvm-as-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-as
	ln -sf /usr/bin/llvm-ar-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-ar
	ln -sf /usr/bin/llvm-nm-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-nm
	ln -sf /usr/bin/llvm-objcopy-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-objcopy
	ln -sf /usr/bin/llvm-objdump-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-objdump
	ln -sf /usr/bin/llvm-profdata-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-profdata
	ln -sf /usr/bin/llvm-symbolizer-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llvm-symbolizer
	ln -sf /usr/bin/opt-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/opt
	ln -sf /usr/bin/llc-$(HOST_LLVM_VERSION) $(HOST_DIR)/bin/llc

	# LLVM libraries expected by llvm-config / CMake exports.
	$(INSTALL) -d $(HOST_DIR)/lib
	$(RM) -f $(HOST_DIR)/lib/libLLVM*.so* \
		$(HOST_DIR)/lib/libLTO*.so* \
		$(HOST_DIR)/lib/libRemarks*.so*
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM-$(HOST_LLVM_VERSION).so \
		$(HOST_DIR)/lib/libLLVM-$(HOST_LLVM_VERSION).so
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM.so.$(HOST_LLVM_VERSION).1 \
		$(HOST_DIR)/lib/libLLVM.so
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM.so.$(HOST_LLVM_VERSION).1 \
		$(HOST_DIR)/lib/libLLVM.so.$(HOST_LLVM_VERSION).1
	ln -sf $(HOST_LLVM_LIBDIR)/libLLVM.so.$(HOST_LLVM_VERSION) \
		$(HOST_DIR)/lib/libLLVM.so.$(HOST_LLVM_VERSION)
	for f in $(HOST_LLVM_PREFIX)/lib/*.so* \
		$(HOST_LLVM_PREFIX)/lib/*.a; do \
		[ -e "$$f" ] || continue; \
		target=$(HOST_DIR)/lib/$$(basename "$$f"); \
		$(RM) -rf "$$target"; \
		ln -sf "$$f" "$$target"; \
	done

	# LLVM headers (llvm/, llvm-c/, etc.).
	$(INSTALL) -d $(HOST_DIR)/include
	for d in $(HOST_LLVM_PREFIX)/include/*/; do \
		[ -d "$$d" ] || continue; \
		target=$(HOST_DIR)/include/$$(basename "$$d"); \
		$(RM) -rf "$$target"; \
		ln -sfn "$$d" "$$target"; \
	done

	# LLVM CMake configs consumed by spirv-llvm-translator, mesa3d, etc.
	$(RM) -rf $(HOST_DIR)/lib/cmake/llvm
	$(INSTALL) -d $(HOST_DIR)/lib/cmake/llvm
	cp -a $(HOST_LLVM_PREFIX)/lib/cmake/llvm/. \
		$(HOST_DIR)/lib/cmake/llvm/

	# libclc data files used by Mesa's OpenCL C compiler.
	$(RM) -rf $(HOST_DIR)/share/libclc
	$(INSTALL) -d $(HOST_DIR)/share/libclc
	cp -a $(HOST_LLVM_PREFIX)/share/libclc/. \
		$(HOST_DIR)/share/libclc/

	# llvm-config must also be visible from staging for target consumers.
	ln -sf $(HOST_DIR)/bin/llvm-config $(STAGING_DIR)/usr/bin/llvm-config
endef

# 4. Host Clang Override
HOST_CLANG_VERSION = 22
HOST_CLANG_PREFIX = /usr/lib/llvm-$(HOST_CLANG_VERSION)
HOST_CLANG_LIBDIR = /usr/lib/$(HOSTARCH)-linux-gnu

HOST_CLANG_SOURCE =
HOST_CLANG_SITE =
HOST_CLANG_DEPENDENCIES = host-llvm
HOST_CLANG_POST_BUILD_HOOKS =
HOST_CLANG_POST_INSTALL_HOOKS =

HOST_CLANG_CONFIGURE_CMDS =
HOST_CLANG_BUILD_CMDS =
define HOST_CLANG_INSTALL_CMDS
	# Clang tools used by other packages and the target build.
	$(INSTALL) -d $(HOST_DIR)/bin
	ln -sf /usr/bin/clang-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang
	ln -sf /usr/bin/clang-$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/bin/clang-$(HOST_CLANG_VERSION)
	ln -sf /usr/bin/clang++-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang++
	ln -sf /usr/bin/clang-cpp-$(HOST_CLANG_VERSION) $(HOST_DIR)/bin/clang-cpp
	ln -sf /usr/bin/clang-tblgen-$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/bin/clang-tblgen
	ln -sf /usr/bin/clang-format-$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/bin/clang-format
	ln -sf /usr/bin/clang-offload-bundler-$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/bin/clang-offload-bundler
	ln -sf /usr/bin/clang-offload-packager-$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/bin/clang-offload-packager

	# Clang libraries expected by CMake exports and libclc.
	$(INSTALL) -d $(HOST_DIR)/lib
	$(RM) -f $(HOST_DIR)/lib/libclang*.so* $(HOST_DIR)/lib/libclang*.a
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang.so
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang.so.1
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-$(HOST_CLANG_VERSION).so.1 \
		$(HOST_DIR)/lib/libclang-$(HOST_CLANG_VERSION).so.$(HOST_CLANG_VERSION)
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_VERSION).1 \
		$(HOST_DIR)/lib/libclang-cpp.so
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_VERSION).1 \
		$(HOST_DIR)/lib/libclang-cpp.so.$(HOST_CLANG_VERSION).1
	ln -sf $(HOST_CLANG_LIBDIR)/libclang-cpp.so.$(HOST_CLANG_VERSION) \
		$(HOST_DIR)/lib/libclang-cpp.so.$(HOST_CLANG_VERSION)
	for f in $(HOST_CLANG_PREFIX)/lib/libclang*.a \
		$(HOST_CLANG_LIBDIR)/libclang*.so*; do \
		[ -e "$$f" ] || continue; \
		target=$(HOST_DIR)/lib/$$(basename "$$f"); \
		$(RM) -rf "$$target"; \
		ln -sf "$$f" "$$target"; \
	done

	# Clang CMake configs.
	$(RM) -rf $(HOST_DIR)/lib/cmake/clang
	$(INSTALL) -d $(HOST_DIR)/lib/cmake/clang
	cp -a $(HOST_CLANG_PREFIX)/lib/cmake/clang/. \
		$(HOST_DIR)/lib/cmake/clang/

	# Clang builtin headers used by the compiler runtime.
	$(RM) -rf $(HOST_DIR)/lib/clang/$(HOST_CLANG_VERSION)/include
	$(INSTALL) -d $(HOST_DIR)/lib/clang/$(HOST_CLANG_VERSION)
	ln -sfn $(HOST_CLANG_PREFIX)/lib/clang/$(HOST_CLANG_VERSION)/include \
		$(HOST_DIR)/lib/clang/$(HOST_CLANG_VERSION)/include

	# Clang support files.
	$(RM) -rf $(HOST_DIR)/share/clang
	ln -sfn $(HOST_CLANG_PREFIX)/share/clang $(HOST_DIR)/share/clang
endef

# 5. Host Libclc Override
HOST_LIBCLC_SOURCE =
HOST_LIBCLC_SITE =
HOST_LIBCLC_DEPENDENCIES = host-llvm

HOST_LIBCLC_CONFIGURE_CMDS =
HOST_LIBCLC_BUILD_CMDS =
define HOST_LIBCLC_INSTALL_CMDS
	# Handled by host-llvm installation
endef

endif
