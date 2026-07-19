################################################################################
#
# minui
#
################################################################################

MINUI_VERSION = v20260719
MINUI_DATE = $(MINUI_VERSION:v%=%)
MINUI_DOT_NUMBER = 0
MINUI_RELEASE_BASE = MinUI-$(MINUI_DATE)-$(MINUI_DOT_NUMBER)
MINUI_SITE = https://github.com/jheronimus/MinUI/releases/download/$(MINUI_VERSION)
MINUI_SOURCE = $(MINUI_RELEASE_BASE)-base.zip
MINUI_SITE_METHOD = wget
MINUI_LICENSE = See upstream
MINUI_LICENSE_FILES = README.txt

MINUI_DEPENDENCIES =
MINUI_INSTALL_IMAGES = YES

define MINUI_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/ui/.ui/bin
	mkdir -p $(BINARIES_DIR)/ui/.ui/config
	mkdir -p $(BINARIES_DIR)/ui/.ui/res
	mkdir -p $(BINARIES_DIR)/ui/.cores

	cd $(@D) && unzip -o MinUI.zip

	cp -a $(@D)/.system/minime/. $(BINARIES_DIR)/ui/.ui/
	cd $(BINARIES_DIR)/ui/.ui && for f in bin/*.elf; do \
		[ -f "$$f" ] && mv -f "$$f" "bin/$$(basename "$$f" .elf)"; done

	# Move libmsettings.so next to binaries
	if [ -d $(@D)/.system/minime/lib ]; then \
		cp -a $(@D)/.system/minime/lib/. $(BINARIES_DIR)/ui/.ui/bin/; \
	fi

	# Install cores
	if [ -d $(@D)/.system/minime/cores ]; then \
		cp -a $(@D)/.system/minime/cores/. $(BINARIES_DIR)/ui/.cores/; \
	fi

	# launcher entry point; UI-specific env setup
	printf '%s\n' \
		'#!/bin/sh' \
		'export SDCARD_PATH=/mnt/sdcard' \
		'export SYSTEM_PATH="$$SDCARD_PATH/.ui"' \
		'export USERDATA_PATH="$$SYSTEM_PATH/config"' \
		'export CORES_PATH="$$SDCARD_PATH/.cores"' \
		'export LD_LIBRARY_PATH="$$SYSTEM_PATH/bin"' \
		'export HOME="$$SDCARD_PATH"' \
		'killall keymon 2>/dev/null || true' \
		'[ ! -x "$$SYSTEM_PATH/bin/keymon" ] || "$$SYSTEM_PATH/bin/keymon" > /tmp/keymon.log 2>&1 &' \
		'exec "$$SYSTEM_PATH/bin/minui"' \
		> $(BINARIES_DIR)/ui/.ui/launch.sh
	chmod +x $(BINARIES_DIR)/ui/.ui/launch.sh
endef

$(eval $(generic-package))
