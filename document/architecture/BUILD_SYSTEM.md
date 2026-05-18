# IMX-Forge 构建系统详解

本文档详细介绍 IMX-Forge 项目的构建系统架构，包括构建流程、各脚本职责、环境变量配置、构建产物说明以及快速构建技巧。

---

## 目录

- [1. 构建系统概述](#1-构建系统概述)
- [2. 完整构建流程](#2-完整构建流程)
- [3. 构建脚本职责说明](#3-构建脚本职责说明)
  - [3.1 核心构建脚本](#31-核心构建脚本)
  - [3.2 共享库脚本](#32-共享库脚本)
  - [3.3 辅助脚本](#33-辅助脚本)
- [4. 环境变量配置](#4-环境变量配置)
- [5. 构建产物说明](#5-构建产物说明)
- [6. 快速构建技巧](#6-快速构建技巧)
- [7. 构建流程图](#7-构建流程图)
- [8. 常见问题排查](#8-常见问题排查)

---

## 1. 构建系统概述

IMX-Forge 构建系统是一个为 NXP i.MX6ULL 平台设计的嵌入式 Linux 构建框架。它采用模块化设计，将 U-Boot、Linux 内核和 BusyBox Rootfs 的构建流程分离，同时通过共享库实现统一的日志输出和错误处理。

我们的最终目标，就是跟其他厂家的build.sh一样，一个脚本出系统，但是笔者发现这些厂家的SDK大多数不咋说人话，也不太好维护，索性自己编写一份啦。

---

## 2. 完整构建流程

完整的构建流程包含以下主要步骤：

### 2.1 流程概览

```
┌─────────────────────────────────────────────────────────────────────┐
│                        IMX-Forge 完整构建流程                        │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  环境变量检查    │
                    │  - ARCH         │
                    │  - CROSS_COMPILE│
                    │  - PATH         │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
      ┌───────────┐  ┌───────────┐  ┌───────────┐
      │ 构建 U-Boot│  │构建 Kernel│  │构建BusyBox│
      │           │  │           │  │           │
      │ 1. 依赖检查│  │ 1. 依赖检查│  │ 1. 依赖检查│
      │ 2. 工具链检查│ │ 2. 工具链检查│ │ 2. 工具链检查│
      │ 3. Logo准备│  │ 3. defconfig│ │ 3. defconfig│
      │ 4. 配置   │  │ 4. 配置   │  │ 4. ARM配置修复│
      │ 5. 编译   │  │ 5. 编译   │  │ 5. 编译   │
      │ 6. 验证   │  │ 6. 验证   │  │ 6. 安装   │
      │ 7. 输出   │  │ 7. 输出   │  │ 7. 验证   │
      └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
            │              │              │
            ▼              ▼              ▼
      ┌─────────────────────────────────────────┐
      │            构建产物输出                  │
      │  out/uboot/u-boot-dtb.imx               │
      │  out/linux/arch/arm/boot/zImage         │
      │  out/linux/arch/arm/boot/dts/*.dtb      │
      │  rootfs/nfs/ (NFS Rootfs)               │
      └─────────────────┬───────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │    系统集成与部署    │
              │  - TFTP 网络启动    │
              │  - SD 卡烧录        │
              │  - eMMC 烧录        │
              └─────────────────────┘
```

### 2.2 构建顺序说明

各组件可以独立构建，但如果需要完整构建系统，建议按照以下顺序：

1. **U-Boot**（可选）：如果需要修改启动加载程序
2. **Linux 内核**：核心系统，通常每次都需要更新
3. **BusyBox**：仅当需要修改用户空间工具时才需重新构建

---

## 3. 构建脚本职责说明

### 3.1 核心构建脚本

#### 3.1.1 build-uboot.sh

**位置**：`scripts/build_helper/build-uboot.sh`

**主要职责**：

- U-Boot 交叉编译环境的配置与验证
- 设备树和 defconfig 检查
- Logo 图片的预处理
- U-Boot 镜像的编译与验证
- 生成可烧录的 u-boot-dtb.imx 文件

**关键配置**：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| ARCH | arm | 目标架构 |
| CROSS_COMPILE | arm-none-linux-gnueabihf- | 交叉编译工具链前缀 |
| DEFCONFIG | mx6ull_aes_emmc_defconfig | 默认配置文件 |
| DEFAULT_DEVICE_TREE | imx6ull-14x14-evk-emmc | 默认设备树 |

**构建步骤**：

```bash
# 1. 检查主机依赖
# 通过导入 env-init.sh 调用统一的依赖检查
source "${SCRIPT_DIR}/../init/env-init.sh"
check_uboot_dependencies()
    - 检查 U-Boot 特定依赖
    - 支持交互式安装缺失的依赖
    - 详细的依赖检查请参考: scripts/init/env-init.sh

# 2. 检查交叉工具链
check_toolchain()
    - 验证 ${CROSS_COMPILE}gcc 存在
    - 验证 objcopy, objdump, strip 工具

# 3. 检查设备树文件
check_device_tree()
    - 验证 ${DEFAULT_DEVICE_TREE}.dts 存在

# 4. 检查 defconfig
check_defconfig()
    - 验证 ${DEFCONFIG} 配置文件存在

# 5. 准备 Logo
logo_helper.sh
    - 转换 PNG 为 BMP 格式
    - 调整尺寸为 800x480

# 6. 清理旧构建
do_distclean()
    - 删除并重建 out/uboot 目录

# 7. 配置 U-Boot
do_configure()
    - make ${DEFCONFIG}

# 8. 编译 U-Boot
do_build()
    - make -j${NPROC}

# 9. 验证构建产物
verify_build_artifacts()
    - u-boot (ELF 文件)
    - u-boot.bin (二进制文件)
    - u-boot.dtb (设备树)
    - u-boot-dtb.imx (i.MX 镜像)
```

**输出产物**：

| 文件 | 说明 | 用途 |
|------|------|------|
| `u-boot` | ELF 格式可执行文件 | 调试使用 |
| `u-boot.bin` | 纯二进制文件 | 中间产物 |
| `u-boot.dtb` | 设备树二进制文件 | 硬件配置 |
| `u-boot-dtb.imx` | NXP i.MX 专用镜像格式 | **可烧录到 eMMC/SD 卡** |

---

#### 3.1.2 build-linux.sh

**位置**：`scripts/build_helper/build-linux.sh`

**主要职责**：

- Linux 内核的交叉编译配置
- 内核配置管理 (defconfig)
- 内核镜像和设备树的编译
- 构建产物的架构验证

**关键配置**：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| ARCH | arm | 目标架构 |
| CROSS_COMPILE | arm-none-linux-gnueabihf- | 交叉编译工具链前缀 |
| DEFCONFIG | imx_aes_defconfig | 默认配置文件 |
| FAST_BUILD | 0/1 | 快速构建模式（跳过 distclean） |

**构建步骤**：

```bash
# 1. 检查主机依赖
# 通过导入 env-init.sh 调用统一的依赖检查
source "${SCRIPT_DIR}/../init/env-init.sh"
check_linux_dependencies()
    - 检查 Linux 内核特定依赖
    - 支持交互式安装缺失的依赖
    - 详细的依赖检查请参考: scripts/init/env-init.sh

# 2. 检查交叉工具链
check_toolchain()
    - 验证 ${CROSS_COMPILE}gcc 存在
    - 显示 GCC 版本信息

# 3. 检查 defconfig
check_defconfig()
    - 验证 ${DEFCONFIG} 文件存在

# 4. 清理旧构建（可选）
do_distclean()
    - 仅在非快速构建模式下执行

# 5. 配置内核
do_configure()
    - make ${DEFCONFIG}

# 6. 编译内核
do_build()
    - make -j${NPROC}

# 7. 验证构建产物
verify_build_artifacts()
    - vmlinux (ELF 内核)
    - zImage (压缩内核)
    - .config (配置文件)
    - System.map (符号表)
```

**输出产物**：

| 文件 | 说明 | 用途 |
|------|------|------|
| `vmlinux` | 未压缩的 ELF 内核 | 调试使用 |
| `arch/arm/boot/zImage` | 压缩内核镜像 | **可烧录/网络启动** |
| `System.map` | 内核符号表 | 调试分析 |
| `.config` | 内核配置 | 配置参考 |
| `arch/arm/boot/dts/*.dtb` | 设备树文件 | **硬件配置** |

**快速构建模式**：

```bash
# 使用 --fast-build 跳过 distclean，加速增量编译
./scripts/build_helper/build-linux.sh --fast-build
```

---

#### 3.1.3 build-busybox.sh

**位置**：`scripts/build_helper/build-busybox.sh`

**主要职责**：

- BusyBox 的交叉编译配置
- ARM 特定配置的自动修复
- BusyBox 的安装到 Rootfs
- 符号链接的自动创建

**关键配置**：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| ARCH | arm | 目标架构 |
| CROSS_COMPILE | arm-none-linux-gnueabihf- | 交叉编译工具链前缀 |
| CLEAN_BUILD | 0/1 | 是否清理构建目录 |
| STATIC_BUILD | 0/1 | 是否构建静态二进制 |
| BUILD_ONLY | 0/1 | 仅构建，不安装 |
| INSTALL_ONLY | 0/1 | 仅安装，使用现有构建 |
| TARGET | defconfig/menuconfig/config | 配置目标 |

**构建步骤**：

```bash
# 1. 检查主机依赖
# 通过导入 env-init.sh 调用统一的依赖检查
source "${SCRIPT_DIR}/../init/env-init.sh"
check_busybox_dependencies()
    - 检查 BusyBox 特定依赖
    - 支持交互式安装缺失的依赖
    - 详细的依赖检查请参考: scripts/init/env-init.sh

# 2. 检查交叉工具链
check_toolchain()
    - 验证 ${CROSS_COMPILE}gcc 存在

# 3. 检查 BusyBox 源码
check_busybox_source()
    - 验证源码目录存在
    - 显示 BusyBox 版本

# 4. 清理构建目录（可选）
do_distclean()
    - 仅在 --clean 模式下执行

# 5. 配置 BusyBox
do_configure()
    - make ${TARGET}
    - 支持 defconfig, menuconfig 等

# 6. ARM 配置修复
fix_arm_config()
    - 禁用 CONFIG_SHA1_HWACCEL (x86 only)
    - 禁用 CONFIG_SHA256_HWACCEL (x86 only)
    - 运行 oldconfig 同步依赖

# 7. 编译 BusyBox
do_build()
    - make -j${NPROC}

# 8. 安装 BusyBox
do_install()
    - make install CONFIG_PREFIX=${INSTALL_DIR}
    - 创建符号链接到各种命令

# 9. 验证构建产物
verify_build_artifacts()
    - busybox 二进制文件
    - .config 配置文件
    - 安装目录中的符号链接
```

**命令行选项**：

```bash
# 默认构建：defconfig + build + install
./scripts/build_helper/build-busybox.sh

# 交互式配置
./scripts/build_helper/build-busybox.sh menuconfig

# 仅构建（使用现有 .config）
./scripts/build_helper/build-busybox.sh --build-only

# 仅安装（使用现有构建）
./scripts/build_helper/build-busybox.sh --install-only

# 清理构建
./scripts/build_helper/build-busybox.sh --clean

# 构建静态二进制
./scripts/build_helper/build-busybox.sh --static

# 组合选项
./scripts/build_helper/build-busybox.sh defconfig --clean --static
```

**输出产物**：

| 文件/目录 | 说明 | 用途 |
|-----------|------|------|
| `busybox` | BusyBox 二进制文件 | 主程序 |
| `.config` | BusyBox 配置 | 配置参考 |
| `rootfs/nfs/bin/busybox` | 安装的二进制 | Rootfs 核心 |
| `rootfs/nfs/bin/*` | 符号链接 | 命令快捷方式 |

---

### 3.2 共享库脚本

#### 3.2.1 logging.sh

**位置**：`scripts/lib/logging.sh`

**主要职责**：

- 提供统一的日志输出接口
- 彩色终端输出
- 调试模式支持

**导出变量**：

```bash
# 颜色定义
export LOG_RED='\033[0;31m'      # 错误信息
export LOG_GREEN='\033[0;32m'    # 一般信息
export LOG_YELLOW='\033[1;33m'   # 警告/命令
export LOG_BLUE='\033[0;34m'     # 调试信息
export LOG_NC='\033[0m'          # 重置颜色

# 向后兼容的非前缀版本
export RED="${LOG_RED}"
export GREEN="${LOG_GREEN}"
export YELLOW="${LOG_YELLOW}"
export BLUE="${LOG_BLUE}"
export NC="${LOG_NC}"
```

**日志函数**：

```bash
# 信息日志（绿色）
log_info "message"

# 错误日志（红色，输出到 stderr）
log_error "message"

# 警告日志（黄色）
log_warn "message"

# 调试日志（蓝色，仅在 DEBUG=1 时显示）
log_debug "message"

# 命令日志（黄色）
log_cmd "command"
```

**使用方法**：

```bash
#!/bin/bash

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/../lib"

# 引入共享日志库
source "${SCRIPT_LIB_DIR}/logging.sh"

# 使用日志函数
log_info "构建开始..."
log_warn "检测到可选依赖缺失"
log_error "构建失败！"
```

---

### 3.3 辅助脚本

#### 3.3.1 build_release_uboot.sh

**位置**：`scripts/release_builder/build_release_uboot.sh`

**主要职责**：

- 执行可重现的 U-Boot 发布构建
- 管理 U-Boot 子模块状态
- 应用补丁
- 生成构建信息文件

**构建流程**：

```bash
# Step 1: 重置 U-Boot 子模块到默认分支
# - 检测默认分支
# - 切换并重置到 upstream
# - 清理工作目录

# Step 2: 验证子模块状态
# - 显示当前 commit
# - 显示版本和分支信息

# Step 3: 创建发布分支
# - 命名格式: release-build-YYYYMMDD-<short-sha>

# Step 4: 应用补丁
# - 应用 patches/uboot-imx/charlies_board.patch

# Step 5: 构建
# - 调用 build-uboot.sh 执行实际构建

# Step 6: 生成构建信息
# - 保存到 out/uboot/build_info.txt
```

**可重现构建**：

```bash
# 设置固定的时间戳确保构建可重现
export SOURCE_DATE_EPOCH=1609459200  # 2021-01-01 00:00:00 UTC

# 执行发布构建
./scripts/release_builder/build_release_uboot.sh v0.1.0
```

**构建信息文件**：

```
========================================
U-Boot Release Build Information
========================================
Release Version: v0.1.0
Build Date: Fri Jan  1 00:00:00 UTC 2021
Source Date Epoch: 1609459200

U-Boot Information:
-------------------
Commit: a1b2c3d4e5f6...
Version: lf_v2025.04-rc1
Branch: lf_v2025.04

Patch Information:
------------------
Patch: charlies_board.patch
Files Modified: 15

Build Environment:
------------------
Build Host: hostname
User: username
Toolchain: arm-none-linux-gnueabihf-

========================================
```

---

#### 3.3.2 copy_to_tftp.sh

**位置**：`scripts/server_helper/copy_to_tftp.sh`

**主要职责**：

- 将编译好的内核和设备树复制到 TFTP 目录
- 支持网络启动开发流程

**使用方法**：

```bash
# 使用默认路径
./scripts/server_helper/copy_to_tftp.sh

# 指定自定义路径
./scripts/server_helper/copy_to_tftp.sh \
    --kernel=out/linux/arch/arm/boot/zImage \
    --dts=out/linux/arch/arm/boot/dts/imx6ull-aes.dtb \
    --tftp-path=~/tftp

# 显示帮助
./scripts/server_helper/copy_to_tftp.sh --help
```

**默认路径**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| --kernel | out/linux/arch/arm/boot/zImage | 内核镜像 |
| --dts | out/linux/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | 设备树 |
| --tftp-path | ~/tftp | TFTP 根目录 |

---

#### 3.3.3 logo_helper.sh

**位置**：`scripts/logo_helper/logo_helper.sh`

**主要职责**：

- 将 PNG 格式的 Logo 转换为 U-Boot 可用的 BMP 格式
- 调整图片尺寸
- 处理颜色深度

**使用方法**：

```bash
# 使用默认参数（800x480）
./scripts/logo_helper/logo_helper.sh

# 自定义尺寸
./scripts/logo_helper/logo_helper.sh 1024x768

# 完整参数
./scripts/logo_helper/logo_helper.sh \
    <尺寸> <输入PNG> <输出BMP>

# 示例
./scripts/logo_helper/logo_helper.sh \
    800x480 \
    document/logo/logo.png \
    third_party/uboot-imx/tools/logos/denx.bmp
```

**处理步骤**：

1. 查找 Git 仓库根目录
2. 构建绝对路径
3. 检查 ImageMagick 是否安装
4. 使用 convert 命令转换：
   - 调整尺寸到指定大小
   - 移除 Alpha 通道
   - 设置颜色深度为 8 位
   - 输出 BMP3 格式
5. 复制到目标位置
6. 清理临时文件

---

## 4. 环境变量配置

### 4.1 必需的环境变量

| 变量名 | 值 | 说明 |
|--------|-----|------|
| ARCH | arm | 目标系统架构 |
| CROSS_COMPILE | arm-none-linux-gnueabihf- | 交叉编译工具链前缀 |

这些变量在构建脚本中已经硬编码，通常不需要手动设置。

### 4.2 PATH 配置

确保交叉工具链在 PATH 中：

```bash
# 临时设置（当前会话有效）
export PATH="/opt/arm-gnu-toolchain/bin:$PATH"

# 永久设置（添加到 ~/.bashrc 或 ~/.zshrc）
echo 'export PATH="/opt/arm-gnu-toolchain/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证
which arm-none-linux-gnueabihf-gcc
# 应输出: /opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc
```

### 4.3 可选的环境变量

| 变量名 | 值 | 说明 |
|--------|-----|------|
| DEBUG | 0/1 | 启用调试日志输出 |
| SOURCE_DATE_EPOCH | 时间戳 | 用于可重现构建 |
| NPROC | 数字 | 覆盖自动检测的并行任务数 |

```bash
# 启用调试输出
DEBUG=1 ./scripts/build_helper/build-linux.sh

# 设置固定时间戳
SOURCE_DATE_EPOCH=1609459200 ./scripts/release_builder/build_release_uboot.sh

# 覆盖并行任务数
NPROC=4 ./scripts/build_helper/build-linux.sh
```

---

## 5. 构建产物说明

### 5.1 out/ 目录结构

```
out/
├── linux/                          # Linux 内核构建输出
│   ├── .config                     # 内核配置文件
│   ├── vmlinux                     # ELF 格式内核（未压缩）
│   ├── System.map                  # 内核符号表
│   ├── Module.symvers              # 模块版本信息
│   ├── arch/arm/boot/
│   │   ├── zImage                  # 压缩内核镜像 ← 主要输出
│   │   └── dts/                    # 设备树文件
│   │       ├── nxp/imx/
│   │       │   └── imx6ull-aes.dtb  # 自定义设备树
│   │       └── ...                 # 其他设备树
│   └── build_info.txt              # 构建信息（发布构建）
│
├── uboot/                          # U-Boot 构建输出
│   ├── .config                     # U-Boot 配置文件
│   ├── u-boot                      # ELF 格式 U-Boot
│   ├── u-boot.bin                  # 纯二进制 U-Boot
│   ├── u-boot.dtb                  # 设备树
│   ├── u-boot-dtb.imx              # i.MX 镜像格式 ← 主要输出
│   └── build_info.txt              # 构建信息（发布构建）
│
└── busybox/                        # BusyBox 构建输出
    ├── .config                     # BusyBox 配置文件
    └── busybox                     # BusyBox 二进制文件
```

### 5.2 rootfs/ 目录结构

```
rootfs/
└── nfs/                            # NFS Rootfs 安装目录
    ├── bin/                        # 用户二进制文件
    │   ├── busybox                 # BusyBox 主程序
    │   ├── sh -> busybox           # Shell 符号链接
    │   ├── ls -> busybox
    │   ├── cat -> busybox
    │   └── ...                     # 其他命令符号链接
    ├── sbin/                       # 系统二进制文件
    │   ├── init -> busybox
    │   └── ...
    ├── usr/
    │   ├── bin/
    │   └── sbin/
    ├── etc/                        # 配置文件
    │   ├── inittab                 # init 配置
    │   ├── passwd                  # 用户数据库
    │   ├── group                   # 组数据库
    │   ├── fstab                   # 文件系统表
    │   └── init.d/                 # 启动脚本
    │       └── rcS                 # 启动脚本
    ├── lib/                        # 共享库
    ├── dev/                        # 设备文件
    │   ├── console
    │   ├── null
    │   └── ...
    ├── proc/                       # 虚拟文件系统挂载点
    ├── sys/                        # 虚拟文件系统挂载点
    ├── tmp/                        # 临时文件
    └── linuxrc -> bin/busybox      # init 符号链接
```

### 5.3 主要烧录文件

| 文件 | 用途 | 烧录位置 |
|------|------|----------|
| `out/uboot/u-boot-dtb.imx` | U-Boot 引导程序 | SD 卡偏移 1KB / eMMC |
| `out/linux/arch/arm/boot/zImage` | Linux 内核镜像 | boot 分区 / TFTP |
| `out/linux/arch/arm/boot/dts/*.dtb` | 设备树二进制 | boot 分区 / TFTP |

---

## 6. 快速构建技巧

### 6.1 增量编译

**Linux 内核快速构建**：

```bash
# 跳过 distclean，仅重新编译修改的文件
./scripts/build_helper/build-linux.sh --fast-build
```

**BusyBox 增量构建**：

```bash
# 使用现有配置，仅重新编译
./scripts/build_helper/build-busybox.sh --build-only

# 编译完成后单独安装
./scripts/build_helper/build-busybox.sh --install-only
```

### 6.2 并行编译

构建脚本自动检测 CPU 核心数进行并行编译：

```bash
# 自动检测（推荐）
NPROC=$(nproc)  # 自动获取核心数

# 手动设置
NPROC=8 ./scripts/build_helper/build-linux.sh
```

### 6.3 配置修改后快速重建

**修改内核配置后**：

```bash
cd out/linux
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- menuconfig
cd -
./scripts/build_helper/build-linux.sh --fast-build
```

**修改 U-Boot 配置后**：

```bash
cd out/uboot
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- menuconfig
cd -
# U-Boot 目前不支持快速构建，会完全重新编译
./scripts/build_helper/build-uboot.sh
```

### 6.4 单独编译设备树

**仅编译设备树**：

```bash
# Linux 设备树
make -C third_party/linux-imx \
    ARCH=arm \
    CROSS_COMPILE=arm-none-linux-gnueabihf- \
    O=out/linux \
    dtbs

# U-Boot 设备树
make -C third_party/uboot-imx \
    ARCH=arm \
    CROSS_COMPILE=arm-none-linux-gnueabihf- \
    O=out/uboot \
    dtbs
```

### 6.5 清理与重建

```bash
# 完全清理 U-Boot
rm -rf out/uboot

# 完全清理 Linux
rm -rf out/linux

# 完全清理 BusyBox
rm -rf out/busybox

# 清理 Rootfs 安装
rm -rf rootfs/nfs

# 一键清理所有
rm -rf out/linux out/uboot out/busybox rootfs/nfs
```

---

## 7. 构建流程图

### 7.1 完整系统构建流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         IMX-Forge 完整构建流程                           │
└─────────────────────────────────────────────────────────────────────────┘

                    ┌───────────────────────────┐
                    │   1. 环境准备              │
                    │   - 检查工具链 (arm-none-  │
                    │     linux-gnueabihf-gcc)   │
                    │   - 检查主机依赖 (gcc,     │
                    │     make, bc, etc.)        │
                    │   - 验证 PATH              │
                    └─────────────┬─────────────┘
                                  │
                ┌─────────────────┼─────────────────┐
                │                 │                 │
                ▼                 ▼                 ▼
    ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
    │   2a. 构建 U-Boot  │ │   2b. 构建 Kernel  │ │   2c. 构建 BusyBox │
    │                   │ │                   │ │                   │
    │ ┌───────────────┐ │ │ ┌───────────────┐ │ │ ┌───────────────┐ │
    │ │ Logo 预处理    │ │ │ │ defconfig     │ │ │ │ defconfig     │ │
    │ └───────┬───────┘ │ │ └───────┬───────┘ │ │ └───────┬───────┘ │
    │         │         │ │         │         │ │         │         │
    │ ▼       │         │ │ ▼       │         │ │ ▼       │         │
    │ │ ┌───────────┐ │ │ │ │ ┌───────────┐ │ │ │ │ ┌───────────┐ │ │
    │ │ │ defconfig │ │ │ │ │ │ menuconfig│ │ │ │ │ │ ARM配置修复│ │ │
    │ │ └─────┬─────┘ │ │ │ │ └─────┬─────┘ │ │ │ │ └─────┬─────┘ │ │
    │ │       │       │ │ │ │       │       │ │ │ │       │       │ │
    │ ▼       ▼       ▼ │ │ ▼       ▼       ▼ │ │ │ ▼       ▼       ▼ │ │
    │ │     ┌────────┐ │ │ │     ┌────────┐ │ │ │ │     ┌────────┐ │ │
    │ │     │ make   │ │ │ │     │ make   │ │ │ │ │     │ make   │ │ │
    │ │     │ -jN    │ │ │ │     │ -jN    │ │ │ │ │     │ -jN    │ │ │
    │ │     └───┬────┘ │ │ │     └───┬────┘ │ │ │ │     └───┬────┘ │ │
    │ │         │       │ │ │         │       │ │ │ │         │       │ │
    │ ▼         ▼       ▼ │ │ ▼         ▼       ▼ │ │ │ ▼         │       ▼ │
    │ │   ┌───────────┐ │ │ │ │   ┌───────────┐ │ │ │ │   ┌───────┴─────┐ │ │
    │ │   │ 验证产物   │ │ │ │ │   │ 验证产物   │ │ │ │ │   │ make install│ │ │
    │ │   │ - u-boot  │ │ │ │ │   │ - vmlinux │ │ │ │ │   │ CONFIG_PREFIX││ │
    │ │   │ - .imx    │ │ │ │ │   │ - zImage │ │ │ │ │   └───────┬─────┘ │ │
    │ │   └───────────┘ │ │ │ │   │ - .dtb   │ │ │ │ │           │       │ │
    │ └─────────────────┘ │ │ │   └───────────┘ │ │ │ ▼           ▼       ▼ │
    └─────────────────────┘ │ └─────────────────┘ │ │ └─────────────────────┘
                           │                       │ │
                           ▼                       ▼
                    ┌──────────────────────────────────────┐
                    │        3. 构建产物输出                │
                    │                                       │
                    │  U-Boot:  out/uboot/u-boot-dtb.imx   │
                    │  Kernel:  out/linux/.../zImage       │
                    │  DTB:     out/linux/.../dts/*.dtb    │
                    │  Rootfs:  rootfs/nfs/                │
                    └───────────────────┬──────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
                    ▼                   ▼                   ▼
            ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
            │ 4a. TFTP 启动  │   │ 4b. SD 卡启动  │   │ 4c. eMMC 启动 │
            │               │   │               │   │               │
            │ 复制到 TFTP    │   │ 分区 & 格式化  │   │ U-Boot 命令   │
            │ 配置 U-Boot    │   │ 烧录到 SD 卡   │   │ 或 USB 工具   │
            │ 网络启动       │   │               │   │               │
            └───────────────┘   └───────────────┘   └───────────────┘
```

### 7.2 U-Boot 构建详细流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                        U-Boot 构建流程                               │
└─────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────┐
    │                    build-uboot.sh                          │
    └───────────────────────────────────────────────────────────┘
                              │
                              ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_host_dependencies()                                 │
    │  ├─ build-essential, gcc, make                            │
    │  ├─ bc, bison, flex, device-tree-compiler                │
    │  ├─ python3, swig                                        │
    │  └─ libssl-dev, libgnutls28-dev, libncurses-dev           │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_toolchain()                                         │
    │  ├─ ${CROSS_COMPILE}gcc 存在性检查                         │
    │  ├─ 显示 GCC 版本信息                                      │
    │  └─ objcopy, objdump, strip 工具检查                       │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_device_tree()                                       │
    │  └─ 验证 ${DEFAULT_DEVICE_TREE}.dts 文件存在               │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_defconfig()                                         │
    │  └─ 验证 ${DEFCONFIG} 配置文件存在                          │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  logo_helper.sh                                            │
    │  ├─ 转换 PNG → BMP                                         │
    │  ├─ 调整尺寸 800x480                                       │
    │  └─ 输出到 tools/logos/denx.bmp                           │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_distclean()                                            │
    │  └─ 删除并重建 out/uboot 目录                              │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_configure()                                            │
    │  └─ make ${DEFCONFIG}                                      │
    │      生成 .config 文件                                      │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_build()                                                │
    │  └─ make -j${NPROC}                                        │
    │      编译所有源文件                                          │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  verify_build_artifacts()                                  │
    │  ├─ u-boot (ELF)      → 验证 ARM 架构                       │
    │  ├─ u-boot.bin        → 验证文件大小                       │
    │  ├─ u-boot.dtb        → 验证设备树内容                     │
    │  └─ u-boot-dtb.imx    → 验证 i.MX 镜像格式                 │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │                        构建成功                              │
    │                                                               │
    │  Flashable artifacts:                                        │
    │    ✓ u-boot-dtb.imx (for i.MX boot)                         │
    │    ✓ u-boot-dtb.bin                                         │
    │    ✓ u-boot.dtb                                             │
    └───────────────────────────────────────────────────────────┘
```

### 7.3 Linux 内核构建详细流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Linux 内核构建流程                              │
└─────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────┐
    │                    build-linux.sh                          │
    └───────────────────────────────────────────────────────────┘
                              │
                              ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_host_dependencies()                                 │
    │  ├─ build-essential, gcc, make                            │
    │  ├─ bc, bison, flex, device-tree-compiler                │
    │  ├─ python3                                               │
    │  └─ libssl-dev, libgnutls28-dev, libncurses-dev           │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_toolchain()                                         │
    │  ├─ ${CROSS_COMPILE}gcc 存在性检查                         │
    │  └─ 显示 GCC 版本信息                                      │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_defconfig()                                         │
    │  └─ 验证 ${DEFCONFIG} 配置文件存在                          │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
                     ┌─────────────────────┐
                     │  FAST_BUILD 模式?    │
                     └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │ No                               │ Yes
              ▼                                  ▼
    ┌───────────────────┐            ┌───────────────────┐
    │ do_distclean()    │            │ 跳过 distclean    │
    │ 删除 out/linux/   │            │ 保留现有构建      │
    └─────────┬─────────┘            └─────────┬─────────┘
              │                                │
              └────────────────┬────────────────┘
                               │
                               ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_configure()                                            │
    │  └─ make ${DEFCONFIG}                                      │
    │      生成 .config 文件                                      │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_build()                                                │
    │  └─ make -j${NPROC}                                        │
    │      编译内核和模块                                         │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  verify_build_artifacts()                                  │
    │  ├─ vmlinux (ELF)      → 验证 ARM 架构, 入口地址            │
    │  ├─ zImage             → 验证文件大小                       │
    │  ├─ .config            → 验证存在                           │
    │  └─ System.map         → 验证符号表                         │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │                        构建成功                              │
    │                                                               │
    │  Kernel artifacts:                                            │
    │    ✓ vmlinux (ELF kernel)                                    │
    │    ✓ arch/arm/boot/zImage (compressed kernel)               │
    │    ✓ System.map (symbol table)                               │
    │    ✓ .config (kernel configuration)                          │
    └───────────────────────────────────────────────────────────┘
```

### 7.4 BusyBox 构建详细流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                       BusyBox 构建流程                                │
└─────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────┐
    │                   build-busybox.sh                          │
    └───────────────────────────────────────────────────────────┘
                              │
                              ▼
    ┌───────────────────────────────────────────────────────────┐
    │  参数解析                                                   │
    │  ├─ TARGET (defconfig/menuconfig/config/...)              │
    │  ├─ --clean (清理构建)                                     │
    │  ├─ --static (静态构建)                                    │
    │  ├─ --build-only (仅构建)                                 │
    │  └─ --install-only (仅安装)                               │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_host_dependencies()                                 │
    │  ├─ build-essential, gcc, make                            │
    │  └─ libncurses-dev                                        │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_toolchain()                                         │
    │  └─ ${CROSS_COMPILE}gcc 存在性检查                         │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  check_busybox_source()                                    │
    │  ├─ 验证源码目录存在                                        │
    │  └─ 显示 BusyBox 版本                                      │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [验证通过]
                                 ▼
                     ┌─────────────────────┐
                     │   CLEAN_BUILD?      │
                     └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │ Yes                              │ No
              ▼                                  ▼
    ┌───────────────────┐            ┌───────────────────┐
    │ do_distclean()    │            │ 创建输出目录      │
    │ 删除 out/busybox/ │            │ 如不存在          │
    └─────────┬─────────┘            └─────────┬─────────┘
              │                                │
              └────────────────┬────────────────┘
                               │
                               ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_configure()                                            │
    │  └─ make ${TARGET}                                         │
    │      (defconfig/menuconfig/config/allnoconfig/allyesconfig)│
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  fix_arm_config()                                          │
    │  ├─ 禁用 CONFIG_SHA1_HWACCEL (x86 only)                   │
    │  ├─ 禁用 CONFIG_SHA256_HWACCEL (x86 only)                 │
    │  └─ 运行 oldconfig 同步依赖                                │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_build()                                                │
    │  └─ make -j${NPROC}                                        │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  do_install()                                              │
    │  └─ make install CONFIG_PREFIX=${INSTALL_DIR}             │
    │      创建符号链接到各种命令                                 │
    └────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │  verify_build_artifacts()                                  │
    │  ├─ busybox 二进制     → 验证架构, 文件大小                 │
    │  ├─ .config            → 验证存在                           │
    │  └─ rootfs/nfs/bin/    → 验证安装, 符号链接数               │
    └────────────────────────────┬──────────────────────────────┘
                                 │ [全部验证通过]
                                 ▼
    ┌───────────────────────────────────────────────────────────┐
    │                        构建成功                              │
    │                                                               │
    │  Output directory: out/busybox/                               │
    │    ✓ busybox binary                                           │
    │    ✓ .config                                                  │
    │                                                               │
    │  Install directory: rootfs/nfs/                               │
    │    ✓ bin/busybox and symlinks                                 │
    └───────────────────────────────────────────────────────────┘
```

---

## 8. 常见问题排查

### 8.1 工具链问题

**问题**：`arm-none-linux-gnueabihf-gcc: command not found`

**原因**：工具链未安装或未添加到 PATH

**解决方法**：

```bash
# 1. 检查工具链是否安装
ls /opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc

# 2. 添加到 PATH（临时）
export PATH="/opt/arm-gnu-toolchain/bin:$PATH"

# 3. 添加到 PATH（永久）
echo 'export PATH="/opt/arm-gnu-toolchain/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

### 8.2 依赖缺失问题

**问题**：缺少某个开发库

**解决方法**：

```bash
# Ubuntu/Debian
sudo apt install \
    build-essential gcc make bc bison flex device-tree-compiler \
    python3 swig libssl-dev libgnutls28-dev libncurses-dev \
    python3-pyelftools

# 对于 Logo 转换
sudo apt install imagemagick
```

---

### 8.3 编译错误

**问题**：编译过程中出现错误

**排查步骤**：

1. 查看完整错误信息
2. 确认工具链版本是否兼容
3. 清理后重新编译

```bash
# 完全清理
rm -rf out/<component>

# 重新编译
./scripts/build_helper/build-<component>.sh
```

---

### 8.4 产物验证失败

**问题**：`verify_build_artifacts()` 报告文件缺失

**排查步骤**：

```bash
# 检查构建输出目录
ls -la out/<component>/

# 检查关键文件
file out/<component>/main_binary
readelf -h out/<component>/main_binary | grep Machine

# 如果架构不对，检查 CROSS_COMPILE
echo $CROSS_COMPILE
```

---

### 8.5 Logo 生成失败

**问题**：Logo 转换失败

**解决方法**：

```bash
# 1. 检查 ImageMagick 是否安装
convert --version

# 2. 检查输入文件
ls -la document/logo/logo.png

# 3. 手动测试转换
convert document/logo/logo.png -resize 800x480! -alpha off -depth 8 bmp3:test.bmp
```

---

## 附录

### A. 构建脚本完整列表

| 脚本路径 | 功能 |
|---------|------|
| `scripts/build_helper/build-linux.sh` | Linux 内核构建 |
| `scripts/build_helper/build-uboot.sh` | U-Boot 构建 |
| `scripts/build_helper/build-busybox.sh` | BusyBox 构建 |
| `scripts/lib/logging.sh` | 日志共享库 |
| `scripts/release_builder/build_release_uboot.sh` | U-Boot 发布构建 |
| `scripts/server_helper/copy_to_tftp.sh` | TFTP 复制工具 |
| `scripts/logo_helper/logo_helper.sh` | Logo 转换工具 |

### B. 配置文件位置

| 组件 | 配置文件类型 | 位置 |
|------|-------------|------|
| U-Boot | defconfig | `third_party/uboot-imx/configs/mx6ull_aes_emmc_defconfig` |
| U-Boot | 设备树 | `third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-emmc.dts` |
| Linux | defconfig | `third_party/linux-imx/arch/arm/configs/imx_aes_defconfig` |
| Linux | 设备树 | `third_party/linux-imx/arch/arm/boot/dts/` |
| BusyBox | defconfig | `third_party/busybox/configs/defconfig` |

### C. 参考文档

- [U-Boot 教程](../tutorial/uboot/01_what_is_uboot)
- [Linux 内核教程](../tutorial/kernel/01_kernel_overview)
- [Rootfs 教程](../tutorial/rootfs/01_rootfs_overview)
- [工具链教程](../tutorial/start/01_start_from_toolchain)
- [实践构建指南](../tutorial/practical/02_build_system)

---

**文档版本**：1.0
**最后更新**：2026-03-15
**维护者**：IMX-Forge 项目组
