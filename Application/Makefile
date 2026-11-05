.PHONY: all clean build_clean

APP_VERSION := $(shell cat ../BaseBin/_external/basebin/.version)-$(shell cat ../BaseBin/_external/basebin/.version-roothide)

all: Dopamine.ipa

Dopamine.ipa: build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Ad-Hoc signing Dopamine
	xattr -rc build/Build/Products/Debug-iphoneos/Dopamine.app
	ldid -SDopamine/Dopamine.entitlements build/Build/Products/Debug-iphoneos/Dopamine.app/Dopamine
	ldid -s build/Build/Products/Debug-iphoneos/Dopamine.app
	rm -rf Payload Dopamine.ipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Dopamine.app Payload/Dopamine.app
	zip -Ar Dopamine.ipa Payload
	rm -rf Payload
	rm -rf Dopamine.tipa
	cp Dopamine.ipa Dopamine.tipa
	mv Dopamine.ipa Dopamine-roothide-"$(APP_VERSION)".ipa
	mv Dopamine.tipa Dopamine-roothide-"$(APP_VERSION)".tipa

ifeq ($(NIGHTLY), 1)
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINITIONS='NIGHTLY=1 COMMIT_HASH=\"$(COMMIT_HASH)\"'
else
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
endif
	touch build/Build/Products/Debug-iphoneos/Dopamine.app/Dopamine.roothide
	cp -a Dopamine/Resources/*.deb build/Build/Products/Debug-iphoneos/Dopamine.app/
	cp ../BaseBin/.build/libroothider.dylib build/Build/Products/Debug-iphoneos/Dopamine.app/
	plutil -replace CFBundleIdentifier -string "com.opa334.Dopamine-roothide" build/Build/Products/Debug-iphoneos/Dopamine.app/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(APP_VERSION)" build/Build/Products/Debug-iphoneos/Dopamine.app/Info.plist
# ifeq ($(PALEHIDE), 1)
	make -C Dopamine/Exploits/palera1n package
	cp -a Dopamine/Exploits/palera1n/.framework build/Build/Products/Debug-iphoneos/Dopamine.app/Frameworks/palera1n.framework
# endif


clean:
	make -C Dopamine/Exploits/palera1n clean
	rm -rf build Payload Dopamine.ipa Dopamine.tipa

build_clean:
	rm -rf Payload build

FORCE: ;