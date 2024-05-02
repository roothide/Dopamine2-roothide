TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = lsd cfprefsd
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = rootlesshooks

rootlesshooks_FILES = $(wildcard src/*.x) $(wildcard src/*.c) $(wildcard src/*.m)
rootlesshooks_CFLAGS = -Werror -fobjc-arc
rootlesshooks_LDFLAGS = -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/fallback

src/lsd.x_CFLAGS = -fno-objc-arc #lsd using mrc

include $(THEOS_MAKE_PATH)/tweak.mk

after-rootlesshooks-all::
	install_name_tool -change @loader_path/.jbroot/usr/lib/libsubstrate.dylib @rpath/CydiaSubstrate.framework/CydiaSubstrate $(THEOS_OBJ_DIR)/rootlesshooks.dylib
	ldid -S $(THEOS_OBJ_DIR)/rootlesshooks.dylib
