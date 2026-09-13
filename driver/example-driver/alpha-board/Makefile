# Framework示例驱动 Makefile
#
# 这是一个验证构建工具链的示例驱动
# 不实际驱动任何硬件

# Kernel module definition
obj-m := fake_driver.o

# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux_mainline
KOBJ := $(PROJECT_ROOT)/out/linux

# 输出目录
OUTPUT_DIR := $(PROJECT_ROOT)/out/driver_artifacts/framework/alpha-board

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译Framework示例驱动..."
	@mkdir -p $(OUTPUT_DIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@cp *.ko $(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 示例驱动编译完成: $(OUTPUT_DIR)/fake_driver.ko"
	@echo "⚠️  注意：这是一个虚拟驱动，不实际驱动硬件"

clean:
	@echo "🧹 清理构建产物..."
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)

install: modules
	@echo "📦 示例驱动位置: $(OUTPUT_DIR)"
	@ls -lh $(OUTPUT_DIR)/*.ko 2>/dev/null || echo "无.ko文件"
	@echo ""
	@echo "使用方法："
	@echo "  1. 部署: ./scripts/deploy_driver.sh $(OUTPUT_DIR)"
	@echo "  2. 测试: insmod fake_driver.ko"
	@echo "  3. 查看日志: dmesg | tail"

help:
	@echo "Framework示例驱动 - 用于验证构建工具链"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译示例驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: $(OUTPUT_DIR)"
