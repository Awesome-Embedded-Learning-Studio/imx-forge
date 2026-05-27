# Spinlock Demo Driver Makefile
#
# Linux 7.0 Kernel Module for Spinlock Demonstration

# Kernel module definition
obj-m := spinlock_demo_06_driver.o

# ── 项目配置 ────────────────────────────────────────
PROJECT_ROOT := $(shell realpath $(CURDIR)/../..)
ARCH := arm
CROSS_COMPILE := arm-none-linux-gnueabihf-

# 内核源码路径
KDIR := $(PROJECT_ROOT)/third_party/linux_mainline
KOBJ := $(PROJECT_ROOT)/out/mainline/linux

# 输出目录
OUTPUT_DIR := $(PROJECT_ROOT)/out/driver_artifacts/spinlock_demo_06/alpha-board

.PHONY: all modules clean install help

all: modules

modules:
	@echo "🔨 编译spinlock_demo驱动..."
	@mkdir -p $(OUTPUT_DIR)
	$(MAKE) -C $(KDIR) M=$(CURDIR) O=$(KOBJ) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@cp *.ko $(OUTPUT_DIR)/ 2>/dev/null || true
	@echo "✓ 驱动编译完成: $(OUTPUT_DIR)/spinlock_demo_06_driver.ko"

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
	@echo "  1. 加载驱动: insmod spinlock_demo_06_driver.ko"
	@echo "  2. 设备节点: /dev/spinlock_demo"
	@echo "  3. 卸载驱动: rmmod spinlock_demo_06_driver"
	@echo "  4. 查看日志: dmesg | grep spinlock_demo"
	@echo ""
	@echo "命令示例："
	@echo "  echo 'protected 1000' > /dev/spinlock_demo  # 带锁操作"
	@echo "  echo 'stress 10000' > /dev/spinlock_demo     # 压力测试"

help:
	@echo "Spinlock Demo Driver"
	@echo ""
	@echo "用法："
	@echo "  make           - 编译驱动"
	@echo "  make clean     - 清理构建产物"
	@echo "  make install   - 显示使用说明"
	@echo ""
	@echo "产物位置: $(OUTPUT_DIR)"
