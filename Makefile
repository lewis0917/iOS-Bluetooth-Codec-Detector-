TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc

LIBRARY_NAME = BTCodecUI
BTCodecUI_FILES = BTCodecRootListController.m PreferencesStub.m
BTCodecUI_INSTALL_PATH = /Library/PreferenceBundles/BTCodecUI.bundle
BTCodecUI_CFLAGS = -fobjc-arc
BTCodecUI_LDFLAGS = -F$(THEOS)/sdk/iPhoneOS.sdk/System/Library/PrivateFrameworks -umbrella Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
