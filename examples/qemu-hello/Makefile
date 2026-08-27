# examples/qemu-hello — kernel module + static app for the emulated AES board
#
# Targets:
#   make            build hello_mod.ko (against the mainline kernel tree)
#                   and a statically linked hello_app
#   make install    drop both artifacts into the shared TFTP dir from
#                   driver_helper.conf (slirp TFTP serves it to the guest
#                   at 10.0.2.2; the real board netboots from it too)
#   make clean
#
# This module lives outside driver/ (which scripts/driver_helper manages),
# so the kernel paths mirror scripts/lib/driver_buildlib.sh directly.

KERNEL_TYPE ?= mainline

PROJECT_ROOT  := $(shell realpath $(CURDIR)/../..)
DRIVER_HELPER := $(PROJECT_ROOT)/scripts/driver_helper
ARCH          := arm
CROSS_COMPILE ?= arm-none-linux-gnueabihf-
KDIR          := $(PROJECT_ROOT)/third_party/linux_$(KERNEL_TYPE)
KOBJ          := $(PROJECT_ROOT)/out/$(KERNEL_TYPE)/linux

# single source of truth for the deploy dir: driver_helper.conf
TFTP_DIR := $(shell sed -n 's/^TFTP_DIR="\(.*\)"/\1/p' $(DRIVER_HELPER)/driver_helper.conf)
ifeq ($(TFTP_DIR),)
TFTP_DIR := $(HOME)/tftp
endif

obj-m := hello_mod.o

.PHONY: all app install clean

all: hello_mod.ko hello_app

hello_mod.ko: hello_mod.c
	$(MAKE) -C $(KDIR) O=$(KOBJ) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	        M=$(CURDIR) modules

hello_app: hello_app.c
	$(CROSS_COMPILE)gcc -static -O2 -Wall -o $@ $<

install: all
	cp hello_mod.ko hello_app $(TFTP_DIR)/
	@echo "installed to $(TFTP_DIR) — in the guest:"
	@echo "  tftp -g -r hello_mod.ko 10.0.2.2 && insmod hello_mod.ko"
	@echo "  tftp -g -r hello_app 10.0.2.2 && chmod +x ./hello_app && ./hello_app"

clean:
	$(MAKE) -C $(KDIR) O=$(KOBJ) ARCH=$(ARCH) M=$(CURDIR) clean
	rm -f hello_app
