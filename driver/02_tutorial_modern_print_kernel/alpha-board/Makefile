# Modern Kernel Print Usage Makefile
#
# 演示现代 Linux 内核打印功能

# Kernel module definition
obj-m := modern_print_kernel_base00_driver.o

# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux-${KERNEL_TYPE}
KOBJ := $(PROJECT_ROOT)/out/${KERNEL_TYPE}

# 输出目录
OUTPUT_DIR := $(PROJECT_ROOT)/out/driver_artifacts/modern_print_kernel_base00/alpha-board

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译 modern_print_kernel_base00 驱动..."
	@mkdir -p $(OUTPUT_DIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@cp *.ko $(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 驱动编译完成: $(OUTPUT_DIR)/modern_print_kernel_base00_driver.ko"

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
	@echo "  1. 构建驱动: scripts/driver_helper/build_driver.sh modern_print_kernel_base00 alpha-board"
	@echo "  2. 部署驱动: scripts/driver_helper/deploy_driver.sh modern_print_kernel_base00 alpha-board"
	@echo "  3. 测试驱动: insmod modern_print_kernel_base00_driver.ko"
	@echo "  4. 查看日志: dmesg | tail"

help:
	@echo "Modern Kernel Print Usage - Linux 内核打印功能演示"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: $(OUTPUT_DIR)"
