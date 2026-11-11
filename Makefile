TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon

# Daemon Hook
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc

# Settings UI Bundle
BUNDLE_NAME = BTCodecUI
BTCodecUI_FILES = BTCodecRootListController.m
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles
BTCodecUI_LDFLAGS = -framework Preferences
BTCodecUI_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
