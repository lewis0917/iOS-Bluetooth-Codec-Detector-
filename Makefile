PACKAGE_VERSION       = 1.0.0
THEOS_PACKAGE_SCHEME  = rootless
TARGET                = iphone:clang:16.5:15.0
ARCHS                 = arm64 arm64e
LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/common.mk

# ── 1. Daemon dylib → bluetoothd ──────────────────────────────────────────────
TWEAK_NAME = BTCodecDaemon

BTCodecDaemon_FILES                    = BTCodecHook.x
BTCodecDaemon_CFLAGS                   = -fobjc-arc \
                                         -fvisibility=hidden \
                                         -I$(THEOS_PROJECT_DIR)
BTCodecDaemon_LDFLAGS                  = -Wl,-undefined,dynamic_lookup \
                                         -Wl,-dead_strip
BTCodecDaemon_INSTALL_TARGET_PROCESSES = bluetoothd
BTCodecDaemon_FRAMEWORKS               = Foundation CoreFoundation

include $(THEOS)/makefiles/tweak.mk

# ── 2. SpringBoard UI dylib → SpringBoard ─────────────────────────────────────
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = BTCodecSB

BTCodecSB_FILES                    = BTCodecSB.x
BTCodecSB_CFLAGS                   = -fobjc-arc \
                                     -fvisibility=hidden \
                                     -I$(THEOS_PROJECT_DIR)
BTCodecSB_LDFLAGS                  = -Wl,-undefined,dynamic_lookup \
                                     -Wl,-dead_strip
BTCodecSB_INSTALL_TARGET_PROCESSES = SpringBoard
BTCodecSB_FRAMEWORKS               = Foundation UIKit CoreFoundation AVFoundation

include $(THEOS)/makefiles/tweak.mk

# ── 3. PreferenceLoader bundle ────────────────────────────────────────────────
BUNDLE_NAME = BTCodecUI

BTCodecUI_FILES        = BTCodecRootListController.m
BTCodecUI_CFLAGS       = -fobjc-arc \
                         -fvisibility=hidden \
                         -I$(THEOS_PROJECT_DIR) \
                         -I$(THEOS_PROJECT_DIR)/headers
BTCodecUI_LDFLAGS      = -Wl,-undefined,dynamic_lookup \
                         -Wl,-dead_strip
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles
BTCodecUI_FRAMEWORKS   = Foundation UIKit CoreFoundation

include $(THEOS)/makefiles/bundle.mk

after-install::
	dpkg -i packages/com.btcodectweak_*.deb
	killall bluetoothd
	sbreload
