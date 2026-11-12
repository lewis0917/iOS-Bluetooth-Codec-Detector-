# ── Root project configuration ────────────────────────────────────────────────
THEOS_DEVICE_IP = 127.0.0.1
THEOS_DEVICE_PORT = 2222
ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# ── 1. Daemon (bluetoothd hook / IPC server) ──────────────────────────────────
DAEMON_NAME = BTCodecDaemon
BTCodecDaemon_FILES = BTCodecDaemon.mm
BTCodecDaemon_CFLAGS = -fobjc-arc \
                       -I$(THEOS_PROJECT_DIR) \
                       -I$(THEOS_PROJECT_DIR)/headers
BTCodecDaemon_LDFLAGS = -Wl,-undefined,dynamic_lookup
BTCodecDaemon_INSTALL_PATH = /usr/local/bin

# ── 2. SpringBoard tweek (UI overlay / client hook) ───────────────────────────
TWEAK_NAME = BTCodecSB
BTCodecSB_FILES = Tweak.x BTCodecShared.m
BTCodecSB_CFLAGS = -fobjc-arc \
                   -I$(THEOS_PROJECT_DIR) \
                   -I$(THEOS_PROJECT_DIR)/headers
BTCodecSB_FRAMEWORKS = UIKit Foundation CoreGraphics
BTCodecSB_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

# ── 3. PreferenceLoader bundle ────────────────────────────────────────────────
BUNDLE_NAME = BTCodecUI

BTCodecUI_FILES        = BTCodecRootListController.m
BTCodecUI_CFLAGS       = -fobjc-arc \
                         -I$(THEOS_PROJECT_DIR) \
                         -I$(THEOS_PROJECT_DIR)/headers
BTCodecUI_LDFLAGS      = -Wl,-undefined,dynamic_lookup \
                         -Wl,-dead_strip
BTCodecUI_INSTALL_PATH = /Library/PreferenceLoader/Preferences
BTCodecUI_FRAMEWORKS   = Foundation UIKit CoreFoundation

include $(THEOS_MAKE_PATH)/bundle.mk

# ── Post-package integration ──────────────────────────────────────────────────
internal-stage::
	# Ensure correct rootless staging structure for layout/ if needed
	@echo "Staging BTCodec files..."
