PACKAGE_VERSION       = 1.0.0
THEOS_PACKAGE_SCHEME  = rootless
TARGET                = iphone:clang:latest:15.0
ARCHS                 = arm64 arm64e

LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS)/makefiles/common.mk

TWEAK_NAME += BTCodecDaemon
BTCodecDaemon_FILES                     = BTCodecHook.x
BTCodecDaemon_CFLAGS                    = -fobjc-arc -fvisibility=hidden -I$(THEOS_PROJECT_DIR)
BTCodecDaemon_LDFLAGS                   = -Wl,-dead_strip
BTCodecDaemon_INSTALL_TARGET_PROCESSES  = bluetoothd
BTCodecDaemon_FRAMEWORKS                = Foundation CoreFoundation
BTCodecDaemon_PRIVATE_FRAMEWORKS        = BluetoothManager

TWEAK_NAME += BTCodecUI
BTCodecUI_FILES                     = Tweak.x
BTCodecUI_CFLAGS                    = -fobjc-arc -fvisibility=hidden -I$(THEOS_PROJECT_DIR)
BTCodecUI_LDFLAGS                   = -Wl,-dead_strip
BTCodecUI_INSTALL_TARGET_PROCESSES  = SpringBoard
BTCodecUI_FRAMEWORKS                = Foundation UIKit CoreFoundation AVFoundation

include $(THEOS)/makefiles/tweak.mk
