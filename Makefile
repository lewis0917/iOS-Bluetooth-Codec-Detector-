TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc

# Compile the preference panel as a library to bypass bundle.mk SDK checks
LIBRARY_NAME = BTCodecUI
BTCodecUI_FILES = BTCodecRootListController.m
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles/BTCodecUI.bundle
BTCodecUI_CFLAGS = -fobjc-arc
BTCodecUI_LDFLAGS = -umbrella Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
