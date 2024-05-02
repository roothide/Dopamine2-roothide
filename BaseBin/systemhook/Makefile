TARGET = systemhook.dylib
CC = clang

CFLAGS = -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations -Os -moutline
LDFLAGS = -dynamiclib

ifeq ($(ENABLE_LOGS), 1)
CFLAGS += -DENABLE_LOGS
endif

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c src/*.m src/*.S ../libjailbreak/src/jbclient_xpc.c ../forkfix/src/litehook.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
