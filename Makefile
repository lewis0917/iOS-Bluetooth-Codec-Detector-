TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc

BUNDLE_NAME = BTCodecUI
BTCodecUI_FILES = BTCodecRootListController.m
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles
BTCodecUI_CFLAGS = -fobjc-arc

# Use the standard header search path for private frameworks rather than manual linker flags
BTCodecUI_EXTRA_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
