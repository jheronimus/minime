################################################################################
#
# minui
#
################################################################################

MINUI_VERSION = v20260720
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

define MINUI_EXTRACT_CMDS
	cd $(@D) && unzip -o $(DL_DIR)/minui/$(MINUI_SOURCE)
endef

define MINUI_INSTALL_IMAGES_CMDS
	cd $(@D) && unzip -o MinUI.zip

	# Stage MinUI system directory to .system/
	mkdir -p $(BINARIES_DIR)/ui/.system
	cp -a $(@D)/.system/. $(BINARIES_DIR)/ui/.system/

	# Strip .elf extensions (MinUI convention; Minime expects bare names)
	cd $(BINARIES_DIR)/ui/.system/minime/bin && for f in *.elf; do \
		[ -f "$$f" ] && mv -f "$$f" "$$(basename "$$f" .elf)"; done

	# Download and install extras (emulator paks + tools)
	wget -nd -t 3 --connect-timeout=10 -O $(@D)/extras.zip $(MINUI_SITE)/$(MINUI_RELEASE_BASE)-extras.zip
	cd $(@D) && unzip -o extras.zip
	if [ -d $(@D)/Emus ]; then \
		cp -a $(@D)/Emus $(BINARIES_DIR)/ui/; \
	fi
	if [ -d $(@D)/Tools ]; then \
		cp -a $(@D)/Tools $(BINARIES_DIR)/ui/; \
	fi

	# Minimal launch.sh wrapper — MinUI hardcodes its own paths internally.
	# ui.sh calls the minui binary directly; this wrapper exists as a
	# convenience entry point for debugging or manual use.
	printf '%s\n' \
		'#!/bin/sh' \
		'killall keymon 2>/dev/null || true' \
		'MINIME_BINDIR=/mnt/sdcard/.system/minime/bin' \
		'[ ! -x "$$MINIME_BINDIR/keymon" ] || "$$MINIME_BINDIR/keymon" > /tmp/keymon.log 2>&1 &' \
		'exec "$$MINIME_BINDIR/minui"' \
		> $(BINARIES_DIR)/ui/.system/minime/launch.sh
	chmod +x $(BINARIES_DIR)/ui/.system/minime/launch.sh
endef

$(eval $(generic-package))
