TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = bluetoothd SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BTCodecDaemon BTCodecUI

# Daemon Hook
BTCodecDaemon_FILES = BTCodecHook.x
BTCodecDaemon_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

# Settings UI
BTCodecUI_FILES = BTCodecRootListController.m
BTCodecUI_PRIVATE_FRAMEWORKS = Preferences
BTCodecUI_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 bluetoothd SpringBoard"
