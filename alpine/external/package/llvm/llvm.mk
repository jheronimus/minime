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
# Replicate the symlinking configuration from host-llvm-system
HOST_LLVM_SOURCE =
HOST_LLVM_SITE =
HOST_LLVM_DEPENDENCIES = host-llvm-system
HOST_LLVM_POST_INSTALL_HOOKS =

HOST_LLVM_CONFIGURE_CMDS =
HOST_LLVM_BUILD_CMDS =
define HOST_LLVM_INSTALL_CMDS
	# Handled by host-llvm-system
endef

# 4. Host Clang Override
# Replicate the symlinking configuration from host-clang-system
HOST_CLANG_SOURCE =
HOST_CLANG_SITE =
HOST_CLANG_DEPENDENCIES = host-clang-system
HOST_CLANG_POST_BUILD_HOOKS =
HOST_CLANG_POST_INSTALL_HOOKS =

HOST_CLANG_CONFIGURE_CMDS =
HOST_CLANG_BUILD_CMDS =
define HOST_CLANG_INSTALL_CMDS
	# Handled by host-clang-system
endef

# 5. Host Libclc Override
# Replicate the symlinking configuration from host-libclc-system
HOST_LIBCLC_SOURCE =
HOST_LIBCLC_SITE =
HOST_LIBCLC_DEPENDENCIES = host-libclc-system

HOST_LIBCLC_CONFIGURE_CMDS =
HOST_LIBCLC_BUILD_CMDS =
define HOST_LIBCLC_INSTALL_CMDS
	# Handled by host-libclc-system
endef

endif
