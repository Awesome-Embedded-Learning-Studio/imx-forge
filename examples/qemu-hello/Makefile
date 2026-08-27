# examples/qemu-hello — kernel module + static app for the emulated AES board
#
# Targets:
#   make            build hello_mod.ko (against the mainline kernel tree)
#                   and a statically linked hello_app
#   make install    drop both artifacts into ~/tftp (slirp TFTP shares this
#                   with the guest at 10.0.2.2; the real board netboots from
#                   the same directory)
#   make clean
#
# The toolchain must be on PATH:
#   export PATH=/opt/arm-gnu-toolchain/bin:$PATH

KERNEL_TYPE ?= mainline

PROJECT_ROOT  := $(shell realpath $(CURDIR)/../..)
ARCH          := arm
CROSS_COMPILE ?= arm-none-linux-gnueabihf-
KDIR          := $(PROJECT_ROOT)/third_party/linux_$(KERNEL_TYPE)
KOBJ          := $(PROJECT_ROOT)/out/$(KERNEL_TYPE)/linux
TFTP_DIR      ?= $(HOME)/tftp

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
