PACKAGE_VERSION       = 1.0.0
THEOS_PACKAGE_SCHEME  = rootless
TARGET                = iphone:clang:16.5:15.0
ARCHS                 = arm64 arm64e
LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon

BTCodecDaemon_FILES                    = BTCodecHook.x
BTCodecDaemon_CFLAGS                   = -fobjc-arc \
                                         -fvisibility=hidden \
                                         -I$(THEOS_PROJECT_DIR)
BTCodecDaemon_LDFLAGS                  = -Wl,-undefined,dynamic_lookup \
                                         -Wl,-dead_strip
BTCodecDaemon_INSTALL_TARGET_PROCESSES = bluetoothd
BTCodecDaemon_FRAMEWORKS               = Foundation CoreFoundation

TWEAK_NAME += BTCodecSB

BTCodecSB_FILES                    = Tweak.x
BTCodecSB_CFLAGS                   = -fobjc-arc \
                                     -fvisibility=hidden \
                                     -I$(THEOS_PROJECT_DIR)
BTCodecSB_LDFLAGS                  = -Wl,-undefined,dynamic_lookup \
                                     -Wl,-dead_strip
BTCodecSB_INSTALL_TARGET_PROCESSES = SpringBoard
BTCodecSB_FRAMEWORKS               = Foundation UIKit CoreFoundation AVFoundation

include $(THEOS)/makefiles/tweak.mk

BUNDLE_NAME = BTCodecUI

BTCodecUI_FILES    = BTCodecRootListController.m
BTCodecUI_CFLAGS   = -fobjc-arc \
                     -fvisibility=hidden \
                     -I$(THEOS_PROJECT_DIR) \
                     -I$(THEOS_PROJECT_DIR)/headers
BTCodecUI_LDFLAGS  = -Wl,-undefined,dynamic_lookup \
                     -Wl,-dead_strip
BTCodecUI_FRAMEWORKS = Foundation UIKit CoreFoundation

include $(THEOS)/makefiles/bundle.mk

internal-stage::
	@if [ -d $(THEOS_STAGING_DIR)/var/jb/BTCodecUI.bundle ]; then \
		mkdir -p $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceLoader/Preferences; \
		cp -r $(THEOS_STAGING_DIR)/var/jb/BTCodecUI.bundle \
			$(THEOS_STAGING_DIR)/var/jb/Library/PreferenceLoader/Preferences/; \
		rm -rf $(THEOS_STAGING_DIR)/var/jb/BTCodecUI.bundle; \
	fi

after-install::
	install.exec "killall bluetoothd; sbreload"
