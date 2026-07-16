################################################################################
#
# minime-prebuilt-llvm
#
################################################################################

MINIME_PREBUILT_LLVM_VERSION = 1
MINIME_PREBUILT_LLVM_LICENSE = Apache-2.0 with exceptions, NCSA, MIT

HOST_MINIME_PREBUILT_LLVM_CHANNEL_URL = $(call qstrip,$(BR2_PACKAGE_MINIME_PREBUILT_LLVM_CHANNEL_URL))
HOST_MINIME_PREBUILT_LLVM_FLAVOR = $(call qstrip,$(BR2_PACKAGE_MINIME_PREBUILT_LLVM_FLAVOR))

# This package intentionally has no Buildroot-managed SOURCE. The channel
# manifest is mutable by design, while the artifact URL it points at is
# immutable and sha256-verified by the fetch script.
HOST_MINIME_PREBUILT_LLVM_SOURCE =

ifneq ($(BR2_PACKAGE_MINIME_PREBUILT_LLVM),y)
HOST_MINIME_PREBUILT_LLVM_INSTALL_CMDS = true
else

define HOST_MINIME_PREBUILT_LLVM_EXTRACT_CMDS
	$(Q)mkdir -p $(@D)
	$(Q)python3 $(BR2_EXTERNAL_MINIME_PATH)/package/minime-prebuilt-llvm/fetch-prebuilt-llvm.py \
		--channel-url '$(HOST_MINIME_PREBUILT_LLVM_CHANNEL_URL)' \
		--buildroot-version '$(BR2_VERSION)' \
		--flavor '$(HOST_MINIME_PREBUILT_LLVM_FLAVOR)' \
		--cache-dir '$(DL_DIR)/minime-prebuilt-llvm' \
		--output-dir '$(@D)'
endef

HOST_MINIME_PREBUILT_LLVM_INSTALL_CMDS = true
endif

$(eval $(host-generic-package))
