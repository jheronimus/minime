################################################################################
#
# benchmark
#
################################################################################

BENCHMARK_VERSION = local
BENCHMARK_SITE = $(MINIME_ROOT)/src/benchmark
BENCHMARK_SITE_METHOD = local
BENCHMARK_LICENSE = MIT

define BENCHMARK_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define BENCHMARK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/benchmark $(TARGET_DIR)/usr/bin/benchmark
endef

$(eval $(generic-package))
