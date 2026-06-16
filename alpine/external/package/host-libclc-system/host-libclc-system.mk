################################################################################
#
# host-libclc-system
#
################################################################################

# Marker package for the host libclc virtual dependency.
# The actual libclc data files are installed by host-llvm-system; this package
# ensures that consumers depending on host-libclc are satisfied without
# compiling host-libclc from source.

HOST_LIBCLC_SYSTEM_SOURCE =
HOST_LIBCLC_SYSTEM_SITE =
HOST_LIBCLC_SYSTEM_DEPENDENCIES = host-llvm-system

define HOST_LIBCLC_SYSTEM_INSTALL_CMDS
	# Nothing to install; host-llvm-system already provides the files.
endef

$(eval $(host-generic-package))
