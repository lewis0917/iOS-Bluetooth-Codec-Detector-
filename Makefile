# BTCodecTweak — Makefile

PACKAGE_VERSION       = 1.0.0
THEOS_PACKAGE_SCHEME  = rootless
TARGET                = iphone:clang:latest:15.0
ARCHS                 = arm64 arm64e
LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/common.mk

# ── 1. Daemon dylib — injected into bluetoothd ────────────────────────────────
TWEAK_NAME = BTCodecDaemon

BTCodecDaemon_FILES                     = BTCodecHook.x
BTCodecDaemon_CFLAGS                    = -fobjc-arc \
                                          -fvisibility=hidden \
                                          -I$(THEOS_PROJECT_DIR)
BTCodecDaemon_LDFLAGS                   = -Wl,-undefined,dynamic_lookup \
                                          -Wl,-dead_strip
BTCodecDaemon_INSTALL_TARGET_PROCESSES  = bluetoothd
BTCodecDaemon_FRAMEWORKS                = Foundation CoreFoundation
BTCodecDaemon_PRIVATE_FRAMEWORKS        = BluetoothManager

include $(THEOS_MAKE_PATH)/tweak.mk

# ── 2. SpringBoard UI dylib — injected into SpringBoard ───────────────────────
TWEAK_NAME = BTCodecSB

BTCodecSB_FILES                     = Tweak.x
BTCodecSB_CFLAGS                    = -fobjc-arc \
                                      -fvisibility=hidden \
                                      -I$(THEOS_PROJECT_DIR)
BTCodecSB_LDFLAGS                   = -Wl,-undefined,dynamic_lookup \
                                      -Wl,-dead_strip
BTCodecSB_INSTALL_TARGET_PROCESSES  = SpringBoard
BTCodecSB_FRAMEWORKS                = Foundation UIKit CoreFoundation AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

# ── 3. PreferenceLoader bundle ────────────────────────────────────────────────
BUNDLE_NAME = BTCodecUI

BTCodecUI_FILES        = BTCodecRootListController.m
BTCodecUI_CFLAGS       = -fobjc-arc \
                         -fvisibility=hidden \
                         -I$(THEOS_PROJECT_DIR) \
                         -I$(THEOS_PROJECT_DIR)/headers
BTCodecUI_LDFLAGS      = -Wl,-undefined,dynamic_lookup \
                         -Wl,-dead_strip
BTCodecUI_INSTALL_PATH = /Library/PreferenceLoader/Preferences
BTCodecUI_FRAMEWORKS   = Foundation UIKit CoreFoundation

include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall bluetoothd; sbreload"
