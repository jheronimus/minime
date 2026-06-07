################################################################################
#
# panfrost
#
################################################################################

PANFROST_VERSION = 25.0.7r3
PANFROST_SITE = https://github.com/jheronimus/minime/releases/download/panfrost-v$(PANFROST_VERSION)
PANFROST_LICENSE = MIT, GPL-2.0, LGPL-2.1
PANFROST_LICENSE_FILES = COPYING
PANFROST_INSTALL_STAGING = YES
PANFROST_DEPENDENCIES = mesa3d-headers libdrm
PANFROST_PROVIDES = libegl libgles libgbm

define PANFROST_INSTALL_LIBS
	mkdir -p $(1)/usr/lib/panfrost
	cp -dpfr $(PANFROST_DIR)/* $(1)/usr/lib/panfrost/
	ln -sf ../libedit.so.0 $(1)/usr/lib/panfrost/libedit.so.2
endef

define PANFROST_INSTALL_PKGCONFIG
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	printf '%s\n' \
		'prefix=/usr' \
		'libdir=$${prefix}/lib' \
		'includedir=$${prefix}/include' \
		'' \
		'Name: egl' \
		'Description: Mesa Panfrost EGL' \
		'Version: $(PANFROST_VERSION)' \
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
		'Version: $(PANFROST_VERSION)' \
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
		'Version: $(PANFROST_VERSION)' \
		'Libs: -L$${libdir}/panfrost -lgbm' \
		'Cflags: -I$${includedir}' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
endef

define PANFROST_INSTALL_GBM_HEADER
	gbm_header="$$(find $(BUILD_DIR) -path '*/src/gbm/main/gbm.h' -print -quit)"; \
	if [ -z "$$gbm_header" ]; then \
		echo "ERROR: gbm.h not found in mesa3d-headers build dir" >&2; \
		exit 1; \
	fi; \
	$(INSTALL) -D -m 0644 "$$gbm_header" $(STAGING_DIR)/usr/include/gbm.h
endef

define PANFROST_INSTALL_STAGING_CMDS
	$(call PANFROST_INSTALL_LIBS,$(STAGING_DIR))
	$(PANFROST_INSTALL_PKGCONFIG)
	$(PANFROST_INSTALL_GBM_HEADER)
endef

define PANFROST_INSTALL_TARGET_CMDS
	$(call PANFROST_INSTALL_LIBS,$(TARGET_DIR))
endef

$(eval $(generic-package))
