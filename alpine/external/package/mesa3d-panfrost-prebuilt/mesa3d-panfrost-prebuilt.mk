################################################################################
#
# mesa3d-panfrost-prebuilt
#
################################################################################

MESA3D_PANFROST_PREBUILT_VERSION = 25.0.7
MESA3D_PANFROST_PREBUILT_SITE = $(call github,jheronimus,panfrost-prebuilts,v$(MESA3D_PANFROST_PREBUILT_VERSION))
MESA3D_PANFROST_PREBUILT_LICENSE = MIT, GPL-2.0, LGPL-2.1
MESA3D_PANFROST_PREBUILT_LICENSE_FILES = COPYING
MESA3D_PANFROST_PREBUILT_INSTALL_STAGING = YES
MESA3D_PANFROST_PREBUILT_DEPENDENCIES = mesa3d-headers libdrm
MESA3D_PANFROST_PREBUILT_PROVIDES = libegl libgles libgbm

define MESA3D_PANFROST_PREBUILT_INSTALL_LIBS
	mkdir -p $(1)/usr/lib/panfrost
	tar -C $(1)/usr/lib/panfrost --strip-components=4 \
		-xzf $(MESA3D_PANFROST_PREBUILT_DIR)/panfrost-prebuilts-v$(MESA3D_PANFROST_PREBUILT_VERSION).tar.gz
endef

define MESA3D_PANFROST_PREBUILT_INSTALL_PKGCONFIG
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	printf '%s\n' \
		'prefix=/usr' \
		'libdir=$${prefix}/lib' \
		'includedir=$${prefix}/include' \
		'' \
		'Name: egl' \
		'Description: Mesa Panfrost EGL' \
		'Version: $(MESA3D_PANFROST_PREBUILT_VERSION)' \
		'Libs: -L$${libdir}/panfrost -lEGL' \
		'Cflags: -I$${includedir}' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
	printf '%s\n' \
		'prefix=/usr' \
		'libdir=$${prefix}/lib' \
		'includedir=$${prefix}/include' \
		'' \
		'Name: glesv2' \
		'Description: Mesa Panfrost OpenGL ES 2' \
		'Version: $(MESA3D_PANFROST_PREBUILT_VERSION)' \
		'Libs: -L$${libdir}/panfrost -lGLESv2' \
		'Cflags: -I$${includedir}' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc
	printf '%s\n' \
		'prefix=/usr' \
		'libdir=$${prefix}/lib' \
		'includedir=$${prefix}/include' \
		'' \
		'Name: gbm' \
		'Description: Mesa Panfrost GBM' \
		'Version: $(MESA3D_PANFROST_PREBUILT_VERSION)' \
		'Libs: -L$${libdir}/panfrost -lgbm' \
		'Cflags: -I$${includedir}' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
endef

define MESA3D_PANFROST_PREBUILT_INSTALL_GBM_HEADER
	gbm_header="$$(find $(BUILD_DIR) -path '*/src/gbm/main/gbm.h' -print -quit)"; \
	if [ -z "$$gbm_header" ]; then \
		echo "ERROR: gbm.h not found in mesa3d-headers build dir" >&2; \
		exit 1; \
	fi; \
	$(INSTALL) -D -m 0644 "$$gbm_header" $(STAGING_DIR)/usr/include/gbm.h
endef

define MESA3D_PANFROST_PREBUILT_INSTALL_STAGING_CMDS
	$(call MESA3D_PANFROST_PREBUILT_INSTALL_LIBS,$(STAGING_DIR))
	$(MESA3D_PANFROST_PREBUILT_INSTALL_PKGCONFIG)
	$(MESA3D_PANFROST_PREBUILT_INSTALL_GBM_HEADER)
endef

define MESA3D_PANFROST_PREBUILT_INSTALL_TARGET_CMDS
	$(call MESA3D_PANFROST_PREBUILT_INSTALL_LIBS,$(TARGET_DIR))
endef

$(eval $(generic-package))
