TARGET = libroot.dylib
CC = clang

CFLAGS = -I../../BaseBin/.include -Isrc -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -O2
LDFLAGS = -dynamiclib -rpath @loader_path/.jbroot

all: $(TARGET) sign

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c ../../BaseBin/libjailbreak/src/jbclient_xpc.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
	@rm -f libroot.deb

package: all
	@mkdir -p .package/DEBIAN
	@mkdir -p .package/usr/lib
	@mkdir -p .package/var
	@ln -s / .package/var/jb
	@cp control .package/DEBIAN/control
	@cp libroot.dylib .package/usr/lib/libroot.dylib
	@dpkg-deb --root-owner-group -Zzstd -b .package ./libroot.deb
	@rm -rf .package