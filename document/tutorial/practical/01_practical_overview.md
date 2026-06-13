---
title: 实战概述
---

# 实战项目概述：我们要一起构建一个可用的 i.MX6ULL 系统

## 为什么需要这篇实战教程

如果你已经读完了前面的 U-Boot 教程、Linux 内核教程和 Rootfs 教程，你可能会问：我都懂了，但怎么把它们组合成一个能跑起来的系统？

这个问题问得好。说实话，笔者当年也是这么过来的。U-Boot 会编了，内核也会编了，BusyBox 也装上了，但板子就是起不来。要么是 U-Boot 启动完内核就没动静了，要么是内核启动完了找不到 rootfs，要么是 rootfs 挂上了但登录不进去。那种感觉就像你买了一堆乐高零件，但拼出来的东西缺胳膊少腿，怎么看怎么别扭。

问题的根源在于：单独理解每个组件是不够的，你需要理解它们是如何协作的。U-Boot 怎么把控制权交给内核？内核怎么找到 rootfs？rootfs 的 init 程序是谁？这些组件之间的"交接棒"过程，才是嵌入式系统的精髓所在。

所以这篇实战教程的目标很明确：**手把手带你从零构建一个完整的 i.MX6ULL 系统**。我们会从最基础的工具链检查开始，一步步编译 U-Boot、Linux 内核、BusyBox rootfs，最后把它们整合到一起，烧录到板子上，看着那个熟悉的登录提示符冒出来。那种成就感，真的不是照着厂商 SDK 跑一遍能比的。

## 实战项目的最终目标

在我们开始之前，先明确一下最终的目标是什么。完成这个实战项目后，你将拥有：

- 一个可以独立启动的 i.MX6ULL 开发板
- 完整的启动链条：ROM Code → U-Boot → Linux Kernel → BusyBox Rootfs
- 可通过串口登录的 shell 环境
- 基本的网络功能（ping、tftp、nfs 挂载）
- 一套可重复构建的脚本和配置

这不是一个"玩具"系统，而是真正可用于开发的基础环境。你可以在此基础上添加自己的驱动、应用程序，把它打造成你想要的样子。

## 你需要具备的预备知识

在开始之前，我假设你已经具备以下基础：

### Linux 基础操作
- 熟悉 Linux 命令行（cd、ls、grep、cat 等）
- 知道如何编辑文本文件（vim 或 nano）
- 了解文件权限和用户管理（sudo、chmod）
- 能够安装软件包（apt）

### 嵌入式开发概念
- 知道什么是交叉编译
- 了解 UART 串口通信
- 理解什么是 bootloader
- 知道设备树的基本概念

### C 语言基础
- 能看懂简单的 C 代码
- 了解编译、链接的基本过程
- 知道什么是静态库和动态库

如果你的某些知识还不够扎实，没关系，实践是最好的老师。遇到不懂的概念，边做边学反而记得更牢。

## 硬件要求

### 开发板
本教程以 **正点原子阿尔法 i.MX6ULL 开发板** 为例，但原理通用，其他基于 i.MX6ULL 的板子也可以参考。

板子需要具备：
- i.MX6ULL 芯片（Cortex-A7，528MHz）
- 至少 256MB DDR3 内存
- eMMC 或 SD 卡存储（我们两种都会讲）
- UART 调试串口
- 以太网接口（可选，但强烈推荐）

### 调试工具
必备：
- USB 转 TTL 串口线（CP2102、CH340、FTDI 都可以）
- 杜邦线若干（母对母，用于连接串口）
- Micro SD 卡和读卡器（如果用 SD 卡启动）

推荐：
- 网线一根（用于网络调试）
- 12V 电源适配器（有些板子可以通过 USB 供电，但独立电源更稳定）

### 开发主机
推荐配置：
- Ubuntu 20.04 / 22.04 / 24.04 LTS
- 至少 4GB 内存
- 至少 20GB 可用磁盘空间
- x86_64 架构

为什么特别强调 Ubuntu？因为大部分嵌入式教程都是基于 Ubuntu 的，遇到问题容易找到解决方案。当然，如果你用 Debian、Arch Linux 之类的发行版也没问题，只是包管理命令可能不太一样。

WSL（Windows Subsystem for Linux）也是可行的选择，笔者就在 WSL2 上完成了大部分开发工作。但要注意串口设备访问的问题，WSL 对串口的支持还需要额外配置。

## 软件环境要求

### 操作系统
- Ubuntu 24.04 及以上版本
- 或者其他 Linux 发行版（Debian、Arch、Fedora 等）

### 必备软件包

在开始之前，请确保你的系统已经安装了以下软件包：

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    git \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    libgnutls28-dev \
    libncurses-dev \
    device-tree-compiler \
    python3 \
    python3-pip \
    swig \
    u-boot-tools \
    qemu-user-static \
    binfmt-support
```

这些包的作用我们会在后续章节中详细解释。现在先装上，避免编译到一半报错。

### 交叉编译工具链

本教程使用的工具链是 **Arm GNU Toolchain 15.2.rel1**：

```bash
arm-none-linux-gnueabihf-gcc
```

详细的工具链安装方法请参考项目中的工具链教程 `document/tutorial/start/01_start_from_toolchain.md`。

简单来说，你需要：
1. 下载 ARM 官方的工具链
2. 解压到 `/opt/arm-gnu-toolchain/`
3. 将 `/opt/arm-gnu-toolchain/bin/` 加入 PATH
4. 验证工具链可用：`arm-none-linux-gnueabihf-gcc -v`

哦对，串口的话，笔者习惯是到Windows上看的，XShell比较方便，我看很多嵌入式的程序员喜欢.

## 完整构建流程概览

在我们深入细节之前，先从全局的角度看一下整个构建流程。这就像登山前先看地图，心里有数才不会迷路。

```
┌─────────────────────────────────────────────────────────────────┐
│                        开发主机 (Ubuntu)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   工具链     │───>│    U-Boot    │───>│ u-boot.imx   │      │
│  │ arm-none-    │    │   编译        │    │              │      │
│  │ linux-gnueabihf│    │              │    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   工具链     │───>│  Linux内核   │───>│   zImage     │      │
│  │              │    │   编译        │    │   .dtb       │      │
│  │              │    │              │    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   工具链     │───>│   BusyBox    │───>│  rootfs/     │      │
│  │              │    │   编译        │    │  目录结构     │      │
│  │              │    │              │    │              │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              整合与打包                                   │   │
│  │  SD卡镜像 / eMMC分区 / 网络启动                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 烧录 / 网络传输
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    i.MX6ULL 开发板                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────┐    ┌─────┐    ┌─────┐    ┌──────────────┐             │
│  │ ROM │───>│U-Boot│───>│Kernel│───>│   Rootfs     │             │
│  │Code│    │      │    │      │    │  (/sbin/init) │             │
│  └─────┘    └─────┘    └─────┘    └──────────────┘             │
│                                                                   │
│              最终目标：看到登录提示符                              │
│              Please press Enter to activate this console.        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

这个流程图展示了从主机编译到板子启动的完整路径。每个环节都有其作用：

1. **工具链**：把源代码编译成 ARM 能执行的机器码
2. **U-Boot**：板子上电后运行的第一个程序，负责初始化硬件和加载内核
3. **Linux 内核**：操作系统的核心，管理系统资源和驱动硬件
4. **Rootfs**：用户空间，包含所有用户程序和配置文件
5. **整合打包**：把各组件组装成可烧录的镜像

## 各组件版本选择说明

### U-Boot 版本
我们使用 NXP 维护的 U-Boot 分支，基于 **v2025.04**：

```
仓库：nxp-imx/uboot-imx
分支：lf_v2025.04
```

为什么用 NXP 分支而不是主线？因为 NXP 分支包含了 i.MX6ULL 的特定支持，比如 DDR 初始化代码、电源管理、特定的外设驱动等。主线 U-Boot 也在逐步加入这些支持，但可能还不够完善。

### Linux 内核版本
我们使用 NXP 维护的 **linux-imx** 内核，版本 **6.12.3**：

```
仓库：nxp-imx/linux-imx
版本：rel/imx/6.12.3-1.0.0
```

同样的理由，NXP 内核包含了 i.MX 系列芯片的完整驱动支持。主线内核也有支持，但某些外设（如 GPU、VPU）的驱动可能不完整。

### BusyBox 版本
我们使用 BusyBox **1.37.0**：

### 工具链版本
我们使用 ARM 官方的 **Arm GNU Toolchain 15.2.rel1**：

```
版本：15.2.rel1
目标：arm-none-linux-gnueabihf
```

这是 ARM 官方维护的最新稳定版本，支持所有新的 C/C++ 标准，生成的代码优化也更好。不用担心"太新"的问题，Linux 内核和 U-Boot 都在持续跟进新的工具链版本。

## 预期结果展示

在我们完成整个构建流程后，你应该能在串口终端看到类似这样的输出：

```
U-Boot 2025.04-00017-gXXXXXXX (Mar 15 2026 - 10:30:00 +0800)

CPU:   Freescale i.MX6ULL rev1.1 528 MHz
Reset cause: POR
Model: Freescale i.MX6ULL 14x14 EVK Board
DRAM:  512 MiB
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
Loading Environment from MMC...

Net:   ethernet@02188000

Hit any key to stop autoboot...  3

=>

# 启动内核
=> bootz 0x82000000 - 0x88000000
Kernel image @ 0x82000000 [ 0x000000 - 0x67a000 ]
## Flattened Device Tree blob at 0x88000000
   Booting using the fdt blob at 0x88000000
Loading Device Tree to 0x87fff000, end 0x88005b9f ... OK

Starting kernel ...

[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 6.12.3 (charliechen@ubuntu) (arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409) #1 SMP PREEMPT Sat Mar 15 10:25:00 CST 2026
[    0.000000] CPU: ARMv7 Processor [410fc075] revision 5 (ARMv7), cr=10c5387d
[    0.000000] CPU: div instructions available: patching division code
[    0.000000] CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
[    0.000000] OF: fdt: Machine model: Freescale i.MX6ULL 14x14 EVK Board
...
[    2.345678] Freeing unused kernel memory: 1024K
[    2.456789] Run /sbin/init as init process
[    3.123456] BusyBox v1.36.1 (2026-03-15 10:20:00 +0800) multi-call binary.
[    3.234567] mounting /etc/fstab failed
[    3.345678] Please press Enter to activate this console.
[    4.456789] input: ttyAMA0 as /class/tty/tty0

/ # uname -a
Linux imx6ull 6.12.3 #1 SMP PREEMPT Sat Mar 15 10:25:00 CST 2026 armv7l GNU/Linux

/ # cat /proc/cpuinfo
processor	: 0
BogoMIPS	: 264.00
Features	: half thumb fastmult vfp edsp neon vfpv3 tls vfpd32
CPU implementer	: 0x41
CPU architecture: 7
CPU variant	: 0x2
CPU part	: 0xc07
CPU revision	: 5

/ # free -h
              total        used        free      shared  buff/cache   available
Mem:          487Mi        24Mi       440Mi       1.0Mi        22Mi       456Mi
Swap:            0B          0B          0B

/ #
```

看到这个提示符，恭喜你，你已经成功构建了一个完整的嵌入式 Linux 系统！

## 预计时间投入

这个实战项目的时间投入取决于你的经验和机器性能：

- 初学者（第一次接触嵌入式 Linux）：2-3 天
- 有一定基础（读过各组件教程）：1-2 天
- 熟悉流程后重新做一遍）：2-4 小时

大部分时间花在：
- 首次编译（工具链、依赖检查）
- 排查问题（网络、存储、设备树）
- 反复试错（改配置、重新编译、重新烧录）

第一次总是最慢的，这是正常的。等你走通一遍，整个过程就清晰了，后续就是举一反三。

## 学习路径建议

这个实战教程是整个教程体系的"大作业"，建议按以下顺序学习：

```
1. 工具链教程 (document/tutorial/start/01_start_from_toolchain.md)
   ↓
2. U-Boot 教程 (document/tutorial/uboot/)
   - 01_what_is_uboot.md
   - 02_uboot_compile.md
   - 04_board_config_basic.md
   ↓
3. Linux 内核教程 (document/tutorial/kernel/)
4. Rootfs 教程 (document/tutorial/rootfs/)
5. 本实战教程 (document/tutorial/practical/)
   - 01_practical_overview.md (本章)
   - 02_build_system.md
   - 03_boot_and_debug.md
```

如果你已经读过了前面的教程，可以直接进入下一章。如果某些概念还不够清楚，建议先回头复习一下相关教程。

## 常见问题提前解答

### Q1：能不能用其他开发板？
可以，但需要调整设备树和某些配置。本教程以正点原子阿尔法为例，如果你的板子不同，主要差异在于设备树文件和引脚配置。

### Q2：必须用 eMMC 吗？
不是，SD 卡启动也可以。教程中会同时介绍两种方式，你可以根据自己的硬件选择。

### Q3：Windows 环境可以吗？
理论上可以，但非常不推荐。嵌入式开发的工具链、脚本、调试工具都是为 Linux 设计的。在 Windows 上折腾 WSL 或虚拟机反而更麻烦。

### Q4：没有以太网接口可以吗？
可以，但网络调试功能会受限。至少初期调试网络相关的问题会困难一些。

### Q5：工具链版本必须严格一致吗？
不必严格一致，但建议不要相差太远。太旧的工具链可能不支持新内核的特性，太新的工具链可能有兼容性问题。

## 预告下一章

到这里，你应该对整个实战项目有了清晰的认识。我们知道了目标是什么，需要什么硬件软件，构建流程是怎样的。

下一章，我们将真正动手开始构建系统。我们会：
1. 验证工具链环境
2. 编译 U-Boot
3. 编译 Linux 内核
4. 构建 BusyBox Rootfs
5. 整合所有组件

准备好了吗？我们开始构建系统！
