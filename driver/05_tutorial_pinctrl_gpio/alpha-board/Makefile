# Pin Control And GPIO Demo Makefile
#
# 由 template_creator.sh 自动生成

# Kernel module definition
obj-m := pinctrl_gpio_demo_04_driver.o
pinctrl_gpio_demo_04_driver-y := pinctrl_gpio_demo_04_driver_main.o led_hw.o
# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux-${KERNEL_TYPE}
KOBJ := $(PROJECT_ROOT)/out/${KERNEL_TYPE}

# 输出目录
OUTPUT_DIR := $(PROJECT_ROOT)/out/driver_artifacts/pinctrl_gpio_demo_04/alpha-board

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译pinctrl_gpio_demo_04驱动..."
	@mkdir -p $(OUTPUT_DIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@cp *.ko $(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 驱动编译完成: $(OUTPUT_DIR)/pinctrl_gpio_demo_04_driver.ko"

clean:
	@echo "🧹 清理构建产物..."
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)

install: modules
	@echo "📦 驱动位置: $(OUTPUT_DIR)"
	@ls -lh $(OUTPUT_DIR)/*.ko 2>/dev/null || echo "无.ko文件"
	@echo ""
	@echo "使用方法："
	@echo "  1. 构建驱动: scripts/driver_helper/build_driver.sh pinctrl_gpio_demo_04 alpha-board"
	@echo "  2. 部署驱动: scripts/driver_helper/deploy_driver.sh pinctrl_gpio_demo_04 alpha-board"
	@echo "  3. 测试驱动: insmod pinctrl_gpio_demo_04_driver.ko"
	@echo "  4. 查看日志: dmesg | tail"

help:
	@echo "Pin Control And GPIO Demo"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: $(OUTPUT_DIR)"
