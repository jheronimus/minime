################################################################################
#
# panfrost
#
################################################################################

PANFROST_VERSION = 26.0.1r4
PANFROST_SITE = https://github.com/minime-os/minime/releases/download/panfrost-v$(PANFROST_VERSION)
PANFROST_LICENSE = MIT, Apache-2.0 with LLVM-exception, GPL-2.0, LGPL-2.1
PANFROST_LICENSE_FILES = COPYING
PANFROST_INSTALL_STAGING = YES
PANFROST_DEPENDENCIES = mesa3d-headers expat libdrm zlib zstd
PANFROST_PROVIDES = libegl libgles libgbm

# New prebuilts are packaged as a sysroot-like tree:
#   usr/lib, usr/lib/pkgconfig, usr/include, COPYING
# Keep support for older usr/lib/panfrost and flat archives to avoid breaking caches.
define PANFROST_INSTALL_LIBS
	mkdir -p $(1)/usr/lib
	if [ -e $(@D)/usr/lib/libEGL.so ] || [ -e $(@D)/usr/lib/libGLESv2.so ] || [ -e $(@D)/usr/lib/libgbm.so ]; then \
		mkdir -p $(1)/usr/lib/panfrost; \
		find $(@D)/usr/lib -mindepth 1 -maxdepth 1 ! -name pkgconfig ! -name panfrost \
			-exec cp -dpfr {} $(1)/usr/lib/panfrost/ \;; \
		for lib in EGL GLESv2 gbm; do \
			find $(1)/usr/lib/panfrost -maxdepth 1 -name "lib$${lib}.so*" \
				-exec sh -c 'for path do ln -snf "panfrost/$$(basename "$$path")" "$(1)/usr/lib/$$(basename "$$path")"; done' sh {} +; \
		done; \
	else \
		mkdir -p $(1)/usr/lib/panfrost; \
		if [ -d $(@D)/usr/lib/panfrost ]; then \
			cp -dpfr $(@D)/usr/lib/panfrost/* $(1)/usr/lib/panfrost/; \
		else \
			find $(@D) -mindepth 1 -maxdepth 1 \
				! -name usr ! -name COPYING ! -name licenses \
				-exec cp -dpfr {} $(1)/usr/lib/panfrost/ \;; \
		fi; \
		for lib in EGL GLESv2 gbm; do \
			find $(1)/usr/lib/panfrost -maxdepth 1 -name "lib$${lib}.so*" \
				-exec sh -c 'for path do ln -snf "panfrost/$$(basename "$$path")" "$(1)/usr/lib/$$(basename "$$path")"; done' sh {} +; \
		done; \
	fi
endef

define PANFROST_INSTALL_PKGCONFIG_FALLBACK
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	printf '%s\n' \
		'prefix=/usr' \
		'libdir=$${prefix}/lib' \
		'includedir=$${prefix}/include' \
		'' \
		'Name: egl' \
		'Description: Mesa Panfrost EGL' \
		'Version: $(PANFROST_VERSION)' \
		'Libs: -L$${libdir} -lEGL' \
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
		'Libs: -L$${libdir} -lGLESv2' \
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
		'Libs: -L$${libdir} -lgbm' \
		'Cflags: -I$${includedir}' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
endef

define PANFROST_INSTALL_DEVEL
	$(PANFROST_INSTALL_PKGCONFIG_FALLBACK)
	if [ -d $(@D)/usr/lib/pkgconfig ]; then \
		cp -dpfr $(@D)/usr/lib/pkgconfig/* $(STAGING_DIR)/usr/lib/pkgconfig/; \
	fi
	if [ -d $(@D)/usr/include ]; then \
		mkdir -p $(STAGING_DIR)/usr/include; \
		cp -dpfr $(@D)/usr/include/* $(STAGING_DIR)/usr/include/; \
	else \
		gbm_header="$$(find $(BUILD_DIR) -path '*/src/gbm/main/gbm.h' -print -quit)"; \
		if [ -z "$$gbm_header" ]; then \
			echo "ERROR: gbm.h not found in mesa3d-headers build dir" >&2; \
			exit 1; \
		fi; \
		$(INSTALL) -D -m 0644 "$$gbm_header" $(STAGING_DIR)/usr/include/gbm.h; \
	fi
endef

define PANFROST_INSTALL_STAGING_CMDS
	$(call PANFROST_INSTALL_LIBS,$(STAGING_DIR))
	$(PANFROST_INSTALL_DEVEL)
endef

define PANFROST_INSTALL_TARGET_CMDS
	$(call PANFROST_INSTALL_LIBS,$(TARGET_DIR))
endef

$(eval $(generic-package))
