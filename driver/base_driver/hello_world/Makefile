# Kernel module definition (read by kernel build system via M=)
obj-m            := hello_world.o
hello_world-objs := hello.o

# ── 以下是正常的项目 Makefile ────────────────────────────────
PROJECT_ROOT  := $(shell realpath $(CURDIR)/../../..)

ARCH          := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

KDIR := $(PROJECT_ROOT)/third_party/linux_mainline
KOBJ := $(PROJECT_ROOT)/out/linux

.PHONY: all modules clean install help

all: modules

modules:
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean 2>/dev/null || true

install: modules
	mkdir -p $(PROJECT_ROOT)/rootfs/nfs/home
	cp $(CURDIR)/hello_world.ko $(PROJECT_ROOT)/rootfs/nfs/home/

help:
	@echo "Usage:"
	@echo "  make                  - Build module with mainline kernel"
	@echo "  make clean            - Clean build artifacts"
	@echo "  make install          - Install to rootfs/nfs/home"