# examples/qemu-icm — read the real icm20608 via the 21-chapter driver
#
#   make            build ./icm_app (static)
#   make driver     build the 21-chapter teaching driver via the verified
#                   scripts/driver_helper pipeline
#   make install    cp icm_app (+ the .ko if present) into the shared
#                   TFTP dir from driver_helper.conf
#   make clean
#
# In the guest (after scripts/qemu_helper/run-qemu.sh, login root/root):
#   udhcpc -i eth1
#   tftp -g -r 21_tutorial_icm20608_spi_driver.ko 10.0.2.2 && insmod 21_tutorial_icm20608_spi_driver.ko
#   tftp -g -r icm_app 10.0.2.2 && chmod +x icm_app && ./icm_app
#
# Rotate the "board" from the QEMU monitor (Ctrl-A C):
#   qom-set /machine/soc/spi2/spi/child[0] accel-x 2048

CROSS_COMPILE ?= arm-none-linux-gnueabihf-
PROJECT_ROOT  := $(shell realpath $(CURDIR)/../..)
DRIVER_HELPER := $(PROJECT_ROOT)/scripts/driver_helper
DRIVER_NAME   := 21_tutorial_icm20608_spi
BOARD         := alpha-board

# single source of truth for the deploy dir: driver_helper.conf
TFTP_DIR := $(shell sed -n 's/^TFTP_DIR="\(.*\)"/\1/p' $(DRIVER_HELPER)/driver_helper.conf)
ifeq ($(TFTP_DIR),)
TFTP_DIR := $(HOME)/tftp
endif

KO := $(PROJECT_ROOT)/out/driver_artifacts/$(DRIVER_NAME)/$(BOARD)/$(DRIVER_NAME)_driver.ko

.PHONY: all driver install clean

all: icm_app

icm_app: icm_app.c
	$(CROSS_COMPILE)gcc -static -O2 -Wall -o $@ $<

driver:
	$(DRIVER_HELPER)/build_driver.sh $(DRIVER_NAME) $(BOARD)

install: all
	cp icm_app $(TFTP_DIR)/
	@if [ -f "$(KO)" ]; then cp "$(KO)" $(TFTP_DIR)/; \
	  echo "installed icm_app + driver .ko to $(TFTP_DIR)"; \
	else \
	  echo "installed icm_app to $(TFTP_DIR); driver .ko missing — run: make driver"; \
	fi

clean:
	rm -f icm_app
