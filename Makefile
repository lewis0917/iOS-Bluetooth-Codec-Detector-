TARGET := iphone:clang:16.5:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon

# Daemon Hook
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

# Settings UI Bundle
BUNDLE_NAME = BTCodecUI
BTCodecUI_FILES = BTCodecRootListController.m
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles
BTCodecUI_PRIVATE_FRAMEWORKS = Preferences
BTCodecUI_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
