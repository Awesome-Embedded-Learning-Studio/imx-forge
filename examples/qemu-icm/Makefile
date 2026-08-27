# examples/qemu-icm — read the real icm20608 via the 21-chapter driver
#
# Builds one static app; the kernel module is the existing teaching driver
# (driver/21_tutorial_icm20608_spi), built with scripts/driver_helper/
# build_driver.sh or taken from out/driver_artifacts.
#
#   make            build ./icm_app (static)
#   make install    cp icm_app + the driver .ko into ~/tftp
#   make clean
#
# In the guest (after run-qemu.sh, root/root):
#   udhcpc -i eth1
#   tftp -g -r 21_tutorial_icm20608_spi_driver.ko 10.0.2.2 && insmod 21_tutorial_icm20608_spi_driver.ko
#   tftp -g -r icm_app 10.0.2.2 && chmod +x icm_app && ./icm_app
#
# Rotate the "board" from the QEMU monitor (Ctrl-A C):
#   qom-set /machine/soc/spi2/spi/child[0] accel-x 2048
#
# Toolchain on PATH: export PATH=/opt/arm-gnu-toolchain/bin:$PATH

CROSS_COMPILE ?= arm-none-linux-gnueabihf-
TFTP_DIR      ?= $(HOME)/tftp
PROJECT_ROOT  := $(shell realpath $(CURDIR)/../..)
KO            := $(PROJECT_ROOT)/out/driver_artifacts/21_tutorial_icm20608_spi/alpha-board/21_tutorial_icm20608_spi_driver.ko

.PHONY: all install clean

all: icm_app

icm_app: icm_app.c
	$(CROSS_COMPILE)gcc -static -O2 -Wall -o $@ $<

install: all
	cp icm_app $(TFTP_DIR)/
	@if [ -f "$(KO)" ]; then cp "$(KO)" $(TFTP_DIR)/; \
	  echo "installed icm_app + driver .ko to $(TFTP_DIR)"; \
	else \
	  echo "installed icm_app; driver .ko missing — build it with:"; \
	  echo "  scripts/driver_helper/build_driver.sh 21_tutorial_icm20608_spi alpha-board"; \
	fi

clean:
	rm -f icm_app
