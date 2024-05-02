export NIGHTLY ?= 1
export ENABLE_LOGS ?= 1

ifeq ($(NIGHTLY), 1)
export COMMIT_HASH = $(shell git describe --tags)
endif

export DOPAMINE_VERSION = $(shell cat ./BaseBin/_external/basebin/.version)

all:
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Packages
	@$(MAKE) -C Application

clean:
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Packages clean
	@$(MAKE) -C Application clean

update: all
	ssh $(DEVICE) "rm -rf /rootfs/var/mobile/Documents/Dopamine.tipa"
	scp -C ./Application/Dopamine.tipa "$(DEVICE):/rootfs/var/mobile/Documents/Dopamine.tipa"
	ssh $(DEVICE) "/basebin/jbctl update tipa /var/mobile/Documents/Dopamine.tipa"

update-basebin: all
	ssh $(DEVICE) "rm -rf /rootfs/var/mobile/Documents/basebin.tar"
	scp -C ./BaseBin/basebin.tar "$(DEVICE):/rootfs/var/mobile/Documents/basebin.tar"
	ssh $(DEVICE) "/basebin/jbctl update basebin /var/mobile/Documents/basebin.tar"

.PHONY: update clean