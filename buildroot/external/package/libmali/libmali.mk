################################################################################
#
# libmali
#
################################################################################

LIBMALI_VERSION = local
LIBMALI_SITE = $(BR2_EXTERNAL_MINIME_PATH)/package/libmali
LIBMALI_SITE_METHOD = local
LIBMALI_LICENSE = proprietary
LIBMALI_LICENSE_FILES = END_USER_LICENCE_AGREEMENT.txt
LIBMALI_INSTALL_STAGING = YES
LIBMALI_PROVIDES = libegl libgles libgbm
LIBMALI_DEPENDENCIES = libdrm host-patchelf

# Map GPU variants to their folder path and original filename
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G31_G24P0),y)
LIBMALI_BOARD = h700
LIBMALI_BLOB = libmali-bifrost-g31-g24p0-gbm.so
endif
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G31_G13P0),y)
LIBMALI_BOARD = rk3326
LIBMALI_BLOB = libmali-bifrost-g31-g13p0-gbm.so
endif
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G31_G2P0),y)
LIBMALI_BOARD = rk3326
LIBMALI_BLOB = libmali-bifrost-g31-g2p0-gbm.so
endif
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G52_G13P0),y)
LIBMALI_BOARD = rk3566
LIBMALI_BLOB = libmali-bifrost-g52-g13p0-gbm.so
endif
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G52_G24P0),y)
LIBMALI_BOARD = rk3566
LIBMALI_BLOB = libmali-bifrost-g52-g24p0-gbm.so
endif
ifeq ($(BR2_PACKAGE_LIBMALI_BIFROST_G52_G2P0),y)
LIBMALI_BOARD = rk3566
LIBMALI_BLOB = libmali-bifrost-g52-g2p0-gbm.so
endif

# Copy the selected blob to the build directory before building
define LIBMALI_COPY_BLOB
	mkdir -p $(@D)/lib/aarch64-linux-gnu
	cp $(BR2_EXTERNAL_MINIME_PATH)/board/$(LIBMALI_BOARD)/overlay/usr/lib/$(LIBMALI_BLOB) \
		$(@D)/lib/aarch64-linux-gnu/libmali-bifrost-$(call qstrip,$(BR2_PACKAGE_LIBMALI_GPU))-$(call qstrip,$(BR2_PACKAGE_LIBMALI_GPU_VERSION))-gbm.so
endef
LIBMALI_POST_EXTRACT_HOOKS += LIBMALI_COPY_BLOB

LIBMALI_CONF_OPTS = \
	-Darch=aarch64 \
	-Dgpu=$(call qstrip,$(BR2_PACKAGE_LIBMALI_GPU)) \
	-Dversion=$(call qstrip,$(BR2_PACKAGE_LIBMALI_GPU_VERSION)) \
	-Dplatform=gbm \
	-Doptimize-level=O0 \
	-Dopencl-icd=false \
	-Dkhr-header=false \
	-Dvendor-package=false \
	-Dwrappers=enabled \
	-Dhooks=true

define LIBMALI_BUILD_SHIM
	$(TARGET_CC) $(TARGET_CFLAGS) -shared -fPIC -O2 -Wall \
		-o $(@D)/libminime_clock_shim.so \
		$(BR2_EXTERNAL_MINIME_PATH)/package/libmali/clock_shim.c \
		-ldl
endef
LIBMALI_POST_BUILD_HOOKS += LIBMALI_BUILD_SHIM

define LIBMALI_INSTALL_SHIM
	$(INSTALL) -D -m 0755 $(@D)/libminime_clock_shim.so \
		$(TARGET_DIR)/usr/lib/libminime_clock_shim.so
	$(INSTALL) -D -m 0755 $(@D)/libminime_clock_shim.so \
		$(STAGING_DIR)/usr/lib/libminime_clock_shim.so
endef
LIBMALI_POST_INSTALL_TARGET_HOOKS += LIBMALI_INSTALL_SHIM

define LIBMALI_PATCH_LIBRARIES
	# Inject hook dependency into every wrapper except libmali itself
	for lib in $(TARGET_DIR)/usr/lib/lib*.so.*; do \
		[ -f "$$lib" ] || continue; \
		[ -L "$$lib" ] && continue; \
		case "$$(basename "$$lib")" in \
			libmali.so*|libmali-hook.so*) continue ;; \
		esac; \
		$(HOST_DIR)/bin/patchelf --print-needed "$$lib" >/dev/null 2>&1 || continue; \
		$(HOST_DIR)/bin/patchelf --add-needed libmali-hook.so.1 "$$lib"; \
	done
	if [ -f $(TARGET_DIR)/usr/lib/libmali-hook.so.1 ]; then \
		$(HOST_DIR)/bin/patchelf --add-needed libmali.so.1 $(TARGET_DIR)/usr/lib/libmali-hook.so.1; \
	fi

	# Inject clock_shim dependency into libmali
	for lib in $(TARGET_DIR)/usr/lib/libmali*.so*; do \
		[ -f "$$lib" ] || continue; \
		[ -L "$$lib" ] && continue; \
		case "$$(basename "$$lib")" in \
			libmali-hook.so*|libminime_clock_shim.so*) continue ;; \
		esac; \
		$(HOST_DIR)/bin/patchelf --print-needed "$$lib" >/dev/null 2>&1 || continue; \
		$(HOST_DIR)/bin/patchelf --add-needed libminime_clock_shim.so "$$lib"; \
	done

	# Drop headers from target_dir to prevent conflicts with standard headers
	rm -rf $(TARGET_DIR)/usr/include
	rm -rf $(TARGET_DIR)/etc/ld.so.conf.d

	# Unversioned symlinks
	cd $(TARGET_DIR)/usr/lib && { \
		[ -f libEGL.so.1 ] && ln -sf libEGL.so.1 libEGL.so || true; \
		[ -f libGLESv2.so.2 ] && ln -sf libGLESv2.so.2 libGLESv2.so || true; \
		[ -f libgbm.so.1 ] && ln -sf libgbm.so.1 libgbm.so || true; \
		[ -f libEGL.so.1 ] || { ln -sf libmali.so libEGL.so.1; ln -sf libmali.so libEGL.so; } || true; \
		[ -f libGLESv2.so.2 ] || { ln -sf libmali.so libGLESv2.so.2; ln -sf libmali.so libGLESv2.so; } || true; \
		[ -f libgbm.so.1 ] || { ln -sf libmali.so libgbm.so.1; ln -sf libmali.so libgbm.so; } || true; \
	}
endef
LIBMALI_POST_INSTALL_TARGET_HOOKS += LIBMALI_PATCH_LIBRARIES

$(eval $(meson-package))
