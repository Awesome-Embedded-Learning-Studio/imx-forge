# IMX-Forge 快速入门指南

> 5分钟快速体验 i.MX6ULL 嵌入式 Linux 系统构建

---

## 目录

1. [项目概述](#项目概述)
2. [环境准备](#环境准备)
3. [获取项目](#获取项目)
4. [快速构建](#快速构建)
5. [烧录启动](#烧录启动)
6. [验证成功](#验证成功)
7. [常见问题](#常见问题)

---

## 开发方式选择

在开始之前，请选择适合您的开发方式：

| 开发方式 | 推荐人群 | 优点 | 缺点 |
|---------|---------|------|------|
| **Docker 环境** | 新手、Windows 用户、国内用户 | • 5分钟快速开始<br>• 环境统一无依赖问题<br>• 跨平台支持<br>• 国内优化加速 | • 需要安装 Docker<br>• 需要熟悉基本 Docker 命令 |
| **主机环境** | Linux 用户、高级开发者 | • 直接访问硬件<br>• 性能略优<br>• 更灵活的调试 | • 工具链配置复杂<br>• 可能遇到依赖冲突<br>• 国内下载较慢 |

**推荐**: 新手和国内用户优先选择 Docker 环境。

**如何使用本指南**:
- **Docker 用户**: 请跳转到 [Docker 快速开始](#docker-快速开始)
- **主机环境用户**: 请继续阅读 [环境准备](#环境准备) 章节

---

## 项目概述

### IMX-Forge 是什么

IMX-Forge 是一个面向 NXP i.MX6ULL 开发板的开源构建系统，它将通常散落在各处的嵌入式开发资源整合在一起：

- **补丁管理** —— 基于 `format-patch + series` 的双轨补丁系统（linux-imx / mainline）
- **构建脚本** —— 一键构建 U-Boot、Linux 内核（NXP BSP / Mainline）、BusyBox Rootfs
- **教程文档** —— 从工具链到系统调试的完整学习路径
- **第三方源码** —— Git Submodule 管理的 U-Boot、Linux、BusyBox、QT 编译流水线

### 能做什么

```
┌─────────────────────────────────────────────────────────────┐
│                    IMX-Forge 构建流程                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  交叉编译工具链 (ARM GNU Toolchain 15.2)                     │
│         ↓                                                     │
│  U-Boot (NXP uboot-imx) → u-boot-dtb.imx                     │
│         ↓                                                     │
│  Linux Kernel (双轨支持)                                      │
│    ├── linux-imx (NXP BSP 6.12.3) → zImage + .dtb           │
│    └── linux_mainline (上游内核) → zImage + .dtb            │
│         ↓                                                     │
│  BusyBox Rootfs → 最小文件系统                               │
│         ↓                                                     │
│  SD/eMMC 镜像 → 可烧录的完整系统                             │
│                                                               │
│  [可选] QT 应用 → qt-compile-pipeline                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### 双轨内核策略

```
patches/
├── [linux-imx]   NXP BSP 6.12.3 ← 稳定推荐
└── [mainline]    上游内核      ← 已完成迁移
```

- **linux-imx**：NXP 官方 BSP，稳定可靠，驱动支持完善
- **mainline**：上游主线内核，长期维护，可向上游贡献

### 适合谁

- **嵌入式开发新手** —— 想学习嵌入式 Linux 但不知道从何入手
- **i.MX6ULL 开发者** —— 需要快速搭建开发环境，避免重复造轮子
- **自制板移植者** —— 需要参考成熟的设备树和补丁配置
- **学习者** —— 想理解完整的嵌入式 Linux 启动链条
- **QT 应用开发者** —— 需要 QT6 交叉编译环境和触摸屏支持

---

## Docker 快速开始

> 本章节适合使用 Docker 开发环境的用户。如果您选择主机环境开发，请跳过本章节。

### 前置要求

- **Docker**: 20.10+ (安装指南: https://docs.docker.com/get-docker/)
- **磁盘空间**: 至少 5GB 可用空间
- **内存**: 建议 4GB 以上可用内存

### 国内用户优化

如果您在中国大陆，建议先配置 Docker 镜像加速器：

```bash
cd docker
sudo bash setup-mirror.sh  # 一键配置国内镜像源
```

### 构建 Docker 镜像

```bash
# 进入项目目录
cd /path/to/imx-forge/docker

# 国内用户使用优化的 Dockerfile
DOCKER_BUILDKIT=1 docker build -f Dockerfile.cn -t imx-forge:latest .

# 国际用户使用标准 Dockerfile
DOCKER_BUILDKIT=1 docker build -t imx-forge:latest .
```

构建时间约 5-10 分钟（取决于网络速度）。

### 运行容器

```bash
# 返回项目根目录
cd ..

# 运行容器（挂载项目目录）
docker run -it --rm \
    -v $(pwd):/workspace \
    -w /workspace \
    imx-forge:latest
```

如果需要使用 USB 设备（烧录）：

```bash
docker run -it --rm \
    --privileged \
    -v /dev:/dev \
    -v $(pwd):/workspace \
    -w /workspace \
    imx-forge:latest
```

### 验证环境

进入容器后，验证工具链：

```bash
arm-none-linux-gnueabihf-gcc --version
```

预期输出：
```
arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
```

### 开始编译

在容器内执行：

```bash
# 一键构建所有组件
./scripts/release-all.sh

# 或分步构建
./scripts/build_helper/build-uboot.sh
./scripts/build_helper/build-linux.sh
./scripts/build_helper/build-busybox.sh
```

### 输出文件

编译产物在 `out/` 目录，与主机环境相同。容器退出后文件仍保留在主机上。

### 下一步

Docker 用户可以直接跳转到 [快速构建](#快速构建) 章节，构建流程与主机环境完全相同。

### 常见问题

- **Q: 镜像构建失败？** 检查网络连接，国内用户使用 Dockerfile.cn
- **Q: 容器内无法访问 USB？** 使用 `--privileged -v /dev:/dev` 参数
- **Q: 编译产物权限问题？** Docker 容器使用 ubuntu 用户(UID 1000)，如有问题请查看 [docker/README.md](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/docker/README.md)

详细文档请参考 [docker/README.md](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/blob/main/docker/README.md)。

---

## 环境准备

### 支持的开发环境

IMX-Forge 在以下环境中测试通过：

| 环境 | 状态 | 备注 |
|------|------|------|
| WSL2 (Ubuntu 22.04/24.04) | ✅ 推荐 | Windows 用户首选，需切换 mirrored 网络模式 |
| Ubuntu 22.04+ | ✅ 推荐 | 原生 Linux 环境 |

### 硬件要求

#### 开发主机
- CPU: 4核心以上（编译时间约15-30分钟）
- 内存: 8GB 以上
- 磁盘: 20GB 可用空间

#### i.MX6ULL 开发板
- **芯片**: NXP i.MX6ULL (Cortex-A7, 528MHz)
- **存储**: eMMC 或 SD 卡（建议 Class 10，至少 4GB）
- **串口**: UART1（默认波特率 115200）
- **网络**: 以太网（可选，用于 TFTP/NFS 网络启动）

#### 必备配件
- USB 转 TTL 串口模块（CP2102/CH340/FT232 等）
- 杜邦线（连接串口）
- SD 卡读卡器
- 网线（可选）

### 软件依赖安装

#### Ubuntu / WSL2

```bash
# 更新软件源
sudo apt update

# 安装基础构建工具
sudo apt install -y build-essential gcc make bc bison flex

# 安装设备树编译器
sudo apt install -y device-tree-compiler

# 安装 SSL 和加密库
sudo apt install -y libssl-dev libgnutls28-dev

# 安装 ncurses（用于 menuconfig）
sudo apt install -y libncurses-dev

# 安装 Python 和工具
sudo apt install -y python3 python3-pyelftools swig

# 安装串口工具
sudo apt install -y picocom minicom

# 安装其他有用工具
sudo apt install -y git wget tree rsync
```

#### 安装 ARM 交叉编译工具链

IMX-Forge 使用 ARM 官方的 GNU Toolchain 15.2：

```bash
# 下载工具链（约 350MB）
cd ~
wget https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 解压
tar -xf arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz

# 安装到 /opt 目录
sudo mv arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain

# 配置 PATH
echo 'export PATH=/opt/arm-gnu-toolchain/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 验证安装
arm-none-linux-gnueabihf-gcc --version
```

预期输出：
```
arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
Copyright (C) 2025 Free Software Foundation, Inc.
```

---

## 获取项目

### 克隆项目

IMX-Forge 使用 Git Submodule 管理第三方源码，需要使用 `--recurse-submodules` 参数：

```bash
# 克隆项目并初始化子模块
git clone --recurse-submodules https://github.com/Awesome-Embedded-Learning-Studio/imx-forge.git

# 或如果已经克隆，更新子模块
cd imx-forge
git submodule update --init --recursive
```

### 项目结构

```
imx-forge/
├── scripts/                # 构建脚本
│   ├── build_helper/      # 主构建脚本
│   │   ├── build-uboot.sh
│   │   ├── build-linux.sh       # NXP BSP 内核
│   │   ├── build-mainline-linux.sh  # 主线内核
│   │   └── build-busybox.sh
│   ├── release-all.sh      # 一键构建所有组件
│   └── patch_maker.sh      # 补丁生成工具
├── third_party/            # 第三方源码（子模块）
│   ├── uboot-imx/          # U-Boot NXP fork
│   ├── linux-imx/          # Linux Kernel NXP BSP
│   ├── linux_mainline/     # Linux Kernel 上游主线
│   ├── busybox/            # BusyBox
│   └── qt-compile-pipeline/  # QT 交叉编译流水线
├── patches/                # 补丁文件
│   ├── linux-imx/
│   ├── linux-mainline/
│   └── uboot/
├── driver/                 # 设备树和驱动
│   ├── device_tree/
│   │   └── alpha-board/    # 正点原子阿尔法板配置
│   ├── base_driver/        # 基础驱动框架
│   ├── led/                # LED 驱动示例
│   └── firmwares/          # 固件
├── examples/               # 示例工程
│   ├── qt/                 # QT 应用示例
│   ├── driver/             # 驱动示例
│   ├── system/             # 系统示例
│   └── project/            # 完整项目示例
├── rootfs/                 # 根文件系统
│   ├── nfs/                # NFS 挂载用 rootfs
│   └── overlay/            # Overlay 叠加目录
├── out/                    # 编译输出目录
├── develop/                # 开发工具
├── tools/                  # 辅助工具
└── document/               # 文档和教程
```

> **Docker 用户注意**: Docker 镜像已包含工具链，无需手动安装 ARM GNU Toolchain。但项目仍需要克隆子模块以获取 U-Boot、Linux 内核等源码。

---

## 快速构建

### 方式一：一键构建（推荐）

IMX-Forge 提供了一键构建脚本，自动完成 U-Boot、Linux 内核和 BusyBox 的编译：

```bash
cd /path/to/imx-forge

# 一键构建所有组件（NXP BSP 内核）
./scripts/release-all.sh

# 或指定只构建某一阶段
./scripts/release-all.sh --stage 1  # 只构建 U-Boot
./scripts/release-all.sh --stage 2  # 只构建内核
./scripts/release-all.sh --stage 3  # 只构建 BusyBox
./scripts/release-all.sh --stage 4  # 只完成 RootFS
```

#### 构建过程解析

**1. U-Boot 构建**

```bash
$ ./scripts/build_helper/build-uboot.sh
```

输出示例：
```
[INFO] Starting U-Boot build for mx6ull_aes_emmc_defconfig
[INFO] ========================================
[INFO] Checking host dependencies...
  ✓ build-essential
  ✓ gcc
  ✓ make
  ✓ device-tree-compiler
  ...
[INFO] Checking toolchain...
Toolchain found: arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1
[INFO] All checks passed, starting build...
[INFO] Running distclean...
[INFO] Configuring U-Boot with mx6ull_aes_emmc_defconfig...
[INFO] Building U-Boot...
...
[INFO] Verifying build artifacts in /home/charliechen/imx-forge/out/uboot...
  ✓ u-boot: ARM
    Entry: 0x87800000
  ✓ u-boot.bin: 613888 bytes
  ✓ u-boot.dtb: i.MX6ULL device tree detected
  ✓ u-boot-dtb.imx: Image Type: ARM Linux Firmware Image (uncompressed)
[INFO] Build completed successfully!
```

关键产物：
- `out/uboot/u-boot-dtb.imx` —— 可烧录的 U-Boot 镜像

**2. Linux 内核构建（NXP BSP）**

```bash
$ ./scripts/build_helper/build-linux.sh
```

输出示例：
```
[INFO] Starting Linux kernel build for imx_aes_defconfig
[INFO] Checking host dependencies...
[INFO] Checking toolchain...
...
[INFO] Building Linux kernel...
  Kernel: arch/arm/boot/zImage is ready
  DTC     arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb
...
[INFO] Build completed successfully!
[INFO] Kernel artifacts in /home/charliechen/imx-forge/out/linux:
  ✓ vmlinux (ELF kernel)
  ✓ arch/arm/boot/zImage (compressed kernel)
  ✓ System.map (symbol table)
```

关键产物：
- `out/linux/arch/arm/boot/zImage` —— 内核镜像
- `out/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb` —— 设备树

**3. Linux 内核构建（Mainline 主线）**

```bash
$ ./scripts/build_helper/build-mainline-linux.sh
```

使用主线内核时，defconfig 为 `imx_aes_mainline_defconfig`，输出目录为 `out/mainline/linux/`。

**4. BusyBox Rootfs 构建**

```bash
$ ./scripts/build_helper/build-busybox.sh
```

输出示例：
```
[INFO] Building BusyBox...
[INFO] Installing BusyBox to /home/charliechen/imx-forge/rootfs/nfs...
[INFO] Verifying build artifacts...
  ✓ busybox: ELF 32-bit LSB executable, ARM, EABI5
  ✓ Symlinks in bin/: 100+
```

关键产物：
- `rootfs/nfs/` —— 完整的根文件系统目录

### 方式二：分步构建（用于调试）

如果想更精细地控制构建过程，可以手动执行每一步：

#### U-Boot 手动构建

```bash
# 设置环境变量
export ARCH=arm
export CROSS_COMPILE=arm-none-linux-gnueabihf-

# 进入源码目录
cd third_party/uboot-imx

# 配置
make mx6ull_aes_emmc_defconfig O=../../out/uboot

# 编译（使用 8 个并行任务）
make -j8 O=../../out/uboot
```

#### Linux 内核手动构建（NXP BSP）

```bash
# 设置环境变量
export ARCH=arm
export CROSS_COMPILE=arm-none-linux-gnueabihf-

# 进入源码目录
cd third_party/linux-imx

# ⚠️ 应用 IMX-Forge 补丁（包含 imx_aes_defconfig）
git apply ../../patches/linux-imx/linux-imx-latest.patch

# 配置（使用 IMX-Forge 自定义的 imx_aes_defconfig）
make imx_aes_defconfig O=../../out/linux

# 如需自定义配置
make menuconfig O=../../out/linux

# 编译
make -j8 O=../../out/linux
```

> **注意：** `imx_aes_defconfig` 是 IMX-Forge 项目自定义配置，需要先应用补丁。如果你想使用 NXP 官方配置，请改用 `imx_v7_defconfig`。

#### Linux 内核手动构建（Mainline）

```bash
# 设置环境变量
export ARCH=arm
export CROSS_COMPILE=arm-none-linux-gnueabihf-

# 进入源码目录
cd third_party/linux_mainline

# 配置
make imx_aes_mainline_defconfig O=../../out/mainline/linux

# 如需自定义配置
make menuconfig O=../../out/mainline/linux

# 编译
make -j8 O=../../out/mainline/linux
```

#### BusyBox 手动构建

```bash
# 设置环境变量
export ARCH=arm
export CROSS_COMPILE=arm-none-linux-gnueabihf-

# 进入源码目录
cd third_party/busybox

# 配置
make defconfig O=../../out/busybox

# 编译并安装
make -j8 O=../../out/busybox
make install O=../../out/busybox CONFIG_PREFIX=../../rootfs/nfs
```

---

## 烧录启动

### 硬件连接

#### 1. 串口连接

使用 USB 转 TTL 模块连接开发板 UART1：

| USB转TTL | i.MX6ULL | 线色 |
|----------|----------|------|
| GND      | GND      | 黑   |
| TX       | RX       | 白   |
| RX       | TX       | 绿   |

> **注意**: TX 接 RX，RX 接 TX（交叉连接）

#### 2. 打开串口终端

```bash
# 查看串口设备
ls /dev/ttyUSB*

# 使用 picocom 打开串口（波特率 115200）
picocom -b 115200 /dev/ttyUSB0
```

picocom 快捷键：
- 退出: `Ctrl + A` → `Ctrl + Q`
- 清屏: `Ctrl + A` → `Ctrl + L`

### SD 卡烧录方案

#### 1. 准备 SD 卡

```bash
# 查看 SD 卡设备（请确认设备名！）
lsblk

# 假设 SD 卡是 /dev/sdX（替换 X 为实际设备）
sudo fdisk -l /dev/sdX
```

#### 2. 分区

```bash
# 卸载所有分区
sudo umount /dev/sdX*

# 使用 fdisk 分区
sudo fdisk /dev/sdX
```

在 fdisk 交互界面执行：
```
o     # 创建新的 DOS 分区表
n     # 新建分区
p     # 主分区
1     # 分区号
      # 默认起始扇区
+100M # 分区大小 100MB（boot 分区）
t     # 修改分区类型
c     # W95 FAT32 (LBA)
n     # 新建分区
p     # 主分区
2     # 分区号
      # 默认起始扇区
      # 默认结束扇区（剩余所有空间，rootfs 分区）
w     # 写入分区表并退出
```

#### 3. 格式化分区

```bash
# 格式化 boot 分区为 FAT32
sudo mkfs.vfat -F 32 /dev/sdX1

# 格式化 rootfs 分区为 EXT4
sudo mkfs.ext4 /dev/sdX2
```

#### 4. 挂载分区

```bash
# 创建挂载点
sudo mkdir -p /mnt/imx-boot
sudo mkdir -p /mnt/imx-root

# 挂载分区
sudo mount /dev/sdX1 /mnt/imx-boot
sudo mount /dev/sdX2 /mnt/imx-root
```

#### 5. 复制文件

```bash
# 复制内核和设备树到 boot 分区
sudo cp out/linux/arch/arm/boot/zImage /mnt/imx-boot/
sudo cp out/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb /mnt/imx-boot/

# 复制 rootfs 到 root 分区
sudo cp -r rootfs/nfs/* /mnt/imx-root/

# 同步并卸载
sync
sudo umount /mnt/imx-boot /mnt/imx-root
```

#### 6. 烧录 U-Boot

```bash
# 烧录 U-Boot 到 SD 卡（跳过第一个扇区）
sudo dd if=out/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc
sync
```

> **警告**: dd 命令具有破坏性，请务必确认设备名正确！

### eMMC 烧录方案

#### 方法一：通过 U-Boot 烧录

1. 先用 SD 卡启动板子
2. 在 U-Boot 命令行执行：

```
=> mmc dev 1 0                    # 切换到 eMMC
=> mmc part                       # 查看 eMMC 分区
=> tftp 0x82000000 u-boot-dtb.imx # 通过 TFTP 下载 U-Boot
=> mmc write 0x82000000 0x2 0x800 # 写入 eMMC（偏移 1KB）
```

#### 方法二：使用 NXP UUU 工具

```bash
# 安装 UUU
sudo apt install libusb-1.0-0-dev
git clone https://github.com/NXPmicro/mfgtools
cd mfgtools
cmake . && make
sudo make install

# 烧录
sudo uuu u-boot-dtb.imx
```

---

## 验证成功

### U-Boot 启动验证

给板子上电，串口终端应显示：

```
U-Boot 2025.04-00017-gXXXXXXX (Mar 15 2026 - 10:30:00 +0800)

CPU:   Freescale i.MX6ULL rev1.1 528 MHz
Reset cause: POR
Model: Freescale i.MX6ULL 14x14 EVK Board
DRAM:  512 MiB
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
Loading Environment from MMC... OK
In:    serial
Out:    serial
Err:    serial
Net:   ethernet@02188000

Hit any key to stop autoboot...  3  2  1
```

### Linux 内核启动验证

U-Boot 启动后，应看到内核日志：

```
Starting kernel ...

[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 6.12.3 (charliechen@ubuntu) (arm-none-linux-gnueabihf-gcc 15.2.1) #1 SMP PREEMPT
[    0.000000] CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=10c5387d
[    0.000000] OF: fdt: Machine model: Freescale i.MX6ULL 14x14 EVK Board
[    0.000000] Memory: 512MiB/512MiB available
...
[    2.345678] console [ttymxc0] enabled
[    2.678901] VFS: Mounted root (ext4 filesystem) readonly on device 179:2.
```

### Rootfs 挂载验证

内核启动完成后，应看到：

```
Please press Enter to activate this console.
```

按回车后，出现登录提示符：

```
/ #
```

### 系统功能验证

```
/ # uname -a
Linux imx6ull 6.12.3 #1 SMP PREEMPT armv7l GNU/Linux

/ # free -h
             total        used        free      shared  buff/cache   available
Mem:          487Mi        24Mi       440Mi       1.0Mi        22Mi       456Mi

/ # cat /proc/cpuinfo | grep Processor
Processor       : ARMv7 Processor rev 5 (v7l)

/ # ls /dev/mmc*
/dev/mmcblk0  /dev/mmcblk0p1  /dev/mmcblk0p2
```

---

## 常见问题

### 问题 1: 串口无输出或乱码

**症状**: 上电后串口完全无输出，或输出乱码。

**原因**:
- TX/RX 接反
- 波特率不匹配
- 串口设备选择错误
- 驱动问题

**解决方法**:
```bash
# 检查串口连接（TX-RX, RX-TX）
# 尝试不同波特率
picocom -b 9600 /dev/ttyUSB0    # 试试 9600
picocom -b 115200 /dev/ttyUSB0  # 标准波特率

# 检查串口设备
ls /dev/ttyUSB* /dev/ttyACM*

# 如果是 WSL2，可能需要 USB 转发
# 参考: https://learn.microsoft.com/en-us/windows/wsl/connect-usb
```

### 问题 2: 编译报错 "command not found"

**症状**: 运行构建脚本时提示某个命令不存在。

**示例输出**:
```
[ERROR] Cross compiler 'arm-none-linux-gnueabihf-gcc' not found!
```

**解决方法**:
```bash
# 检查 PATH 配置
echo $PATH | grep arm-gnu-toolchain

# 手动添加 PATH
export PATH=/opt/arm-gnu-toolchain/bin:$PATH

# 验证工具链
arm-none-linux-gnueabihf-gcc --version

# 如果仍然失败，重新安装工具链（参考"环境准备"章节）
```

### 问题 3: U-Boot 启动后卡住

**症状**: U-Boot 启动到一半就停止了。

**示例输出**:
```
U-Boot 2025.04...
CPU:   Freescale i.MX6ULL rev1.1 528 MHz
DRAM:  512 MiB
```

**可能原因**:
- 环境变量加载失败
- 设备树问题
- 存储设备初始化失败

**解决方法**:
```
=> printenv                # 查看环境变量
=> printenv bootcmd        # 查看启动命令
=> reset                   # 复位重启

# 如果环境变量损坏，恢复默认值
=> env default -a
=> saveenv
```

### 问题 4: 内核启动报错 "VFS: Cannot open root device"

**症状**: 内核启动过程中报错无法挂载根文件系统。

**示例输出**:
```
[    2.345678] VFS: Cannot open root device "mmcblk0p2" or unknown-block(179,2)
[    2.456789] Please append a correct "root=" boot option
```

**解决方法**:
```
=> printenv bootargs
=> setenv bootargs "console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw"
=> saveenv

# 检查分区是否存在
=> mmc part
```

### 问题 5: WSL2 网络无法 ping 通开发板

**症状**: 在 WSL2 中无法与开发板网络通信。

**原因**: WSL2 默认 NAT 模式会隔离开发板网络。

**解决方法**:

1. 在 Windows 上创建 `.wslconfig` 文件：

```ini
[wsl2]
networkingMode=mirrored
```

2. 重启 WSL：
```powershell
wsl --shutdown
wsl
```

3. 验证网络：
```bash
# 在 WSL 中应该能看到与 Windows 相同的网卡
ip addr

# 测试 ping 开发板
ping 192.168.1.100  # 替换为开发板 IP
```

### 问题 6: 子模块初始化失败

**症状**: git submodule update 报错。

**解决方法**:
```bash
# 方法一：递归初始化
git submodule update --init --recursive

# 方法二：单独初始化失败的模块
cd third_party/linux_mainline
git checkout master
cd ../..
git submodule update --remote --merge
```

---

## 下一步

恭喜！你已经成功构建并运行了第一个嵌入式 Linux 系统。

接下来你可以：

1. **深入学习** —— 阅读项目教程文档
   - [工具链教程](./tutorial/start/01_start_from_toolchain)
   - [U-Boot 教程](./tutorial/uboot/01_what_is_uboot)
   - [内核教程](./tutorial/kernel/)
   - [Rootfs 教程](./tutorial/rootfs/01_rootfs_overview)

2. **自定义配置** —— 根据你的需求修改系统
   - 使用 `make menuconfig` 自定义内核配置
   - 修改设备树适配你的硬件
   - 扩展 rootfs 添加更多功能

3. **网络开发** —— 设置 TFTP/NFS 提高开发效率
   - 参考 kernel 网络启动教程

4. **驱动开发** —— 学习编写 Linux 驱动程序
   - 参考 [驱动开发教程](./tutorial/driver/)

5. **QT 应用开发** —— 构建 GUI 应用
   - 使用 qt-compile-pipeline 交叉编译 QT6

---

## 参考资料

- [项目主页](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge) —— GitHub 仓库
- [项目规划](todo/) —— 待办事项
- [U-Boot 官方文档](https://www.denx.de/wiki/U-Boot)
- [Linux 内核文档](https://www.kernel.org/doc/html/latest/)
- [BusyBox 官方网站](https://busybox.net/)

---

## 技术支持

遇到问题？请：

1. 查看 [常见问题](#常见问题) 章节
2. 搜索项目的 [Issues](https://github.com/Awesome-Embedded-Learning-Studio/imx-forge/issues)
3. 提交新的 Issue 并附上完整的日志信息

---

**快速入门指南 —— 让嵌入式 Linux 开发变得简单**

Copyright © 2026 IMX-Forge Project. MIT License.
