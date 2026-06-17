################################################################################
#
# geekbench
#
################################################################################

GEEKBENCH_VERSION = 6.5.0
GEEKBENCH_SOURCE = Geekbench-$(GEEKBENCH_VERSION)-LinuxARMPreview.tar.gz
GEEKBENCH_SITE = https://cdn.geekbench.com
GEEKBENCH_LICENSE = proprietary

define GEEKBENCH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/geekbench6 $(TARGET_DIR)/usr/bin/geekbench6
	$(INSTALL) -D -m 0755 $(@D)/geekbench_aarch64 $(TARGET_DIR)/usr/bin/geekbench_aarch64
	$(INSTALL) -D -m 0644 $(@D)/geekbench.plar $(TARGET_DIR)/usr/bin/geekbench.plar
	$(INSTALL) -D -m 0644 $(@D)/geekbench-workload.plar $(TARGET_DIR)/usr/bin/geekbench-workload.plar
endef

$(eval $(generic-package))
