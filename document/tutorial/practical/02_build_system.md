---
title: 完整系统构建
---

# 从零构建完整系统：U-Boot、Linux 内核与 BusyBox Rootfs 的整合艺术

## 为什么这一章这么重要

如果你已经分别编译过 U-Boot、Linux 内核和 BusyBox，你可能会觉得这一章多此一举。但相信我，真正让系统跑起来，往往不在单个组件的编译，而在于组件之间的协调。

笔者当年就踩过这样的坑：U-Boot 编译成功了，内核也编译成功了，但板子就是起不来。串口输出停在 U-Boot 的某个地方，或者内核启动到一半就挂了。后来排查发现，是 U-Boot 传给内核的设备树地址不对，或者是 bootargs 参数写错了，甚至是 rootfs 的 init 程序路径不对。

所以这一章的目标很明确：**串讲完整的构建流程，确保每个组件都能正确工作，并且能够无缝衔接**。我们会从头到尾走一遍，每一步都验证，确保不把问题留给下一环节。

## 第一步：工具链验证——确保地基牢固

在开始编译之前，我们首先要确认工具链是可用的。这就像盖房子前检查地基，地基不稳，后面再怎么努力也是白搭。

### 检查工具链版本

```bash
arm-none-linux-gnueabihf-gcc --version
```

你应该看到类似这样的输出：

```
arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
Copyright (C) 2025 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO warranty;
not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

关键信息：
- 版本号是 15.2.1（或其他 15.x 版本）
- 目标架构是 ARM

如果输出命令不存在，说明工具链没有正确安装或者 PATH 没配置好。请参考工具链教程重新配置。

### 验证工具链的完整性

```bash
# 检查常用的工具链组件
which arm-none-linux-gnueabihf-gcc
which arm-none-linux-gnueabihf-ld
which arm-none-linux-gnueabihf-objcopy
which arm-none-linux-gnueabihf-objdump
which arm-none-linux-gnueabihf-strip
```

每个命令都应该输出一个路径，比如 `/opt/arm-gnu-toolchain/bin/arm-none-linux-gnueabihf-gcc`。如果有任何一个命令找不到，说明工具链安装不完整。

### 测试编译一个简单的程序

写一个最简单的 C 程序测试：

```bash
echo 'int main() { return 0; }' | arm-none-linux-gnueabihf-gcc -x c - -o /tmp/test_arm
file /tmp/test_arm
```

应该看到：

```
/tmp/test_arm: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV)...
```

关键信息：
- ELF 32-bit
- ARM 架构
- EABI5

如果不是 ARM 架构，说明你用错了编译器（可能用了系统的 gcc）。

## 前序知识回顾

在开始本章之前，建议你已经阅读或了解：

1. **工具链教程** ([../start/01_start_from_toolchain.md](../start/01_start_from_toolchain))
   - 交叉编译的原理
   - ARM GNU Toolchain 的安装和验证

2. **U-Boot 教程** ([../uboot/01_what_is_uboot.md](../uboot/01_what_is_uboot))
   - U-Boot 在启动链条中的作用
   - U-Boot 的基本概念和命令

3. **Linux 内核教程** ([../kernel/01_kernel_overview.md](../kernel/01_kernel_overview))
   - 内核的基本概念
   - 主线内核与厂商BSP的区别

4. **Rootfs 教程** ([../rootfs/01_rootfs_overview.md](../rootfs/01_rootfs_overview))
   - Rootfs 的作用和组成
   - BusyBox 的基本概念

如果你对以上内容还不够熟悉，建议先花些时间阅读相关教程。理解了这些基础概念，本章的实战操作会更有意义。

---

## 第二步：U-Boot 编译——系统的第一道门

> **知识点回顾**：如果你对 U-Boot 的作用、编译原理还不够熟悉，建议先阅读：
> - [01_what_is_uboot.md](../uboot/01_what_is_uboot) - U-Boot 是什么
> - [02_uboot_compile.md](../uboot/02_uboot_compile) - U-Boot 编译详解
>
> 本实战教程将使用项目提供的构建脚本简化流程，但理解背后的原理仍然重要。

U-Boot 是板子上电后运行的第一个程序，它的正确性直接决定了系统能否启动。我们使用项目提供的构建脚本，确保每一步都正确。

### 获取 U-Boot 源码

U-Boot 源码在 `third_party/uboot-imx/` 目录下，以 Git Submodule 的形式管理：

```bash
cd /home/charliechen/imx-forge
git submodule update --init --remote third_party/uboot-imx
```

### 运行构建脚本

项目提供了完整的构建脚本 `scripts/build_helper/build-uboot.sh`：

```bash
cd /home/charliechen/imx-forge
./scripts/build_helper/build-uboot.sh
```

### 脚本执行过程解析

让我们看一下脚本在做什么：

#### 1. 依赖检查

```bash
[INFO] Checking host dependencies...
  ✓ build-essential
  ✓ gcc
  ✓ make
  ✓ bc
  ✓ bison
  ✓ flex
  ✓ device-tree-compiler
  ✓ python3
  ✓ swig
  ✓ libssl-dev
  ✓ libgnutls28-dev
  ✓ libncurses-dev
  ✓ python3-pyelftools
```

脚本会检查所有必需的软件包。如果缺少任何一个，会告诉你需要安装什么。

**踩坑记录**：有一次脚本提示缺少 `libgnutls28-dev`，我当时觉得反正不用加密功能，就忽略了。结果编译到 FIT Image 相关代码时报错，浪费了好长时间。

#### 2. 工具链检查

```bash
[INFO] Checking toolchain...
Toolchain found: arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
All required toolchain components found
```

脚本会验证交叉编译器是否存在，版本是否正确。

**经验**：如果你的 PATH 配置了多个工具链，脚本可能会用错版本。建议清理 PATH，只保留需要的工具链。

#### 3. 清理旧的编译产物

```bash
[INFO] Running distclean... Using Remove All as to make all clear!
  Removing /home/charliechen/imx-forge/out/uboot
```

`distclean` 会删除所有编译产物，确保从头开始编译。

**踩坑记录**：有一次我改了 defconfig 但没有 distclean，结果 .config 残留导致修改不生效。排查了好久才发现是缓存问题，从那以后我每次都确保清理干净。

#### 4. 配置 U-Boot

```bash
[INFO] Configuring U-Boot with mx6ull_aes_emmc_defconfig...
make -C third_party/uboot-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/uboot mx6ull_aes_emmc_defconfig
```

这里使用了 `mx6ull_aes_emmc_defconfig` 配置，适配正点原子阿尔法开发板的 eMMC 版本。

配置输出类似：

```
# configuration written to /home/charliechen/imx-forge/out/uboot/.config
```

#### 5. 编译 U-Boot

```bash
[INFO] Building U-Boot...
make -C third_party/uboot-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/uboot -j8
```

`-j8` 表示使用 8 个并行任务，根据你的 CPU 核心数调整。

编译过程会持续一段时间，输出大量信息。正常情况下不会有错误，只有一些警告。

**经验**：编译时间是衡量工具链性能的一个指标。用 15.x 版本的工具链编译 U-Boot，大概需要 2-5 分钟（取决于 CPU）。如果时间过长，可能是工具链或配置有问题。

#### 6. 验证编译产物

```bash
[INFO] Verifying build artifacts in /home/charliechen/imx-forge/out/uboot...
  ✓ u-boot: ARM
    Entry: 0x87800000
  ✓ u-boot.bin: 613888 bytes
  ✓ u-boot.dtb: i.MX6ULL device tree detected
  ✓ u-boot-dtb.imx: Image Type: ARM Linux Firmware Image (uncompressed)
```

脚本会检查关键产物是否正确生成：
- `u-boot`：ELF 格式的可执行文件
- `u-boot.bin`：纯二进制文件
- `u-boot.dtb`：设备树二进制文件
- `u-boot-dtb.imx`：NXP i.MX 专用的镜像格式

**踩坑记录**：有一次 `u-boot-dtb.imx` 没有生成，我排查发现是 mkimage 工具没有正确编译。重新编译解决了问题。

### 编译成功后的输出

```
========================================
Build completed successfully!

Flashable artifacts in /home/charliechen/imx-forge/out/uboot:
  ✓ u-boot-dtb.imx (for i.MX boot)
  ✓ u-boot-dtb.bin
  ✓ u-boot.dtb
========================================
```

最重要的是 `u-boot-dtb.imx` 文件，这是我们烧录到 eMMC 或 SD 卡的文件。

### 手动验证（可选）

如果你想更深入地了解 U-Boot 的编译产物，可以手动验证：

```bash
cd /home/charliechen/imx-forge/out/uboot

# 查看文件大小
ls -lh u-boot.bin u-boot-dtb.imx

# 查看镜像信息
../third_party/uboot-imx/tools/mkimage -l u-boot-dtb.imx

# 反汇编设备树
dtc -I dtb -O dts u-boot.dtb | head -50
```

## 第三步：Linux 内核编译——系统的核心

Linux 内核是操作系统的核心，负责管理硬件资源和提供系统服务。我们继续使用项目提供的构建脚本。

### 获取内核源码

Linux 内核源码在 `third_party/linux-imx/` 目录下：

```bash
cd /home/charliechen/imx-forge
git submodule update --init --remote third_party/linux-imx
```

### 运行构建脚本

```bash
cd /home/charliechen/imx-forge
./scripts/build_helper/build-linux.sh
```

### 脚本执行过程解析

#### 1. 依赖检查

```bash
[INFO] Checking host dependencies...
  ✓ build-essential
  ✓ gcc
  ✓ make
  ✓ bc
  ✓ bison
  ✓ flex
  ✓ device-tree-compiler
  ✓ python3
  ✓ libssl-dev
  ✓ libgnutls28-dev
  ✓ libncurses-dev
```

Linux 内核的依赖与 U-Boot 类似，但多了一些包（如 openssl、gnutls）用于签名和加密功能。

**踩坑记录**：内核编译需要 `bc` 进行一些数学计算，第一次编译时我漏装了，导致 Kconfig 处理时报错。

#### 2. 工具链检查

```bash
[INFO] Checking toolchain...
Toolchain found: arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
All required toolchain components found
```

#### 3. 配置内核

```bash
[INFO] Configuring Linux kernel with imx_aes_defconfig...
make -C third_party/linux-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/linux imx_aes_defconfig
```

这里使用 `imx_aes_defconfig` 配置，针对 i.MX6ULL 平台进行了优化。

> **注意：** `imx_aes_defconfig` 是 IMX-Forge 项目自定义的配置文件（包含通过补丁添加的 AES 板卡支持），在使用前需要确保已应用项目补丁。构建脚本会自动处理补丁应用。

**经验**：如果想自定义内核配置，可以运行 `make menuconfig`：

```bash
make -C third_party/linux-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/linux menuconfig
```

#### 4. 编译内核

```bash
[INFO] Building Linux kernel...
make -C third_party/linux-imx ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/linux -j8
```

内核编译比 U-Boot 要慢得多，可能需要 10-30 分钟（取决于 CPU 和缓存）。

编译过程中的关键信息：

```
  Kernel: arch/arm/boot/zImage is ready
  DTC     arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb
```

这表示内核镜像和设备树已经成功编译。

#### 5. 验证编译产物

```bash
[INFO] Verifying build artifacts in /home/charliechen/imx-forge/out/linux...
  ✓ vmlinux: ARM
    Entry: 0x80008000
  ✓ zImage: 6821504 bytes (6.5 MiB)
  ✓ .config: present
  ✓ System.map: present
```

关键产物说明：
- `vmlinux`：未压缩的内核 ELF 文件，带调试信息
- `zImage`：压缩的内核镜像，这是我们要烧录的文件
- `.config`：内核配置文件
- `System.map`：内核符号表，用于调试

### 编译成功后的输出

```
========================================
Build completed successfully!

Kernel artifacts in /home/charliechen/imx-forge/out/linux:
  ✓ vmlinux (ELF kernel)
  ✓ arch/arm/boot/zImage (compressed kernel)
  ✓ System.map (symbol table)
  ✓ .config (kernel configuration)
========================================
```

### 查找设备树文件

设备树文件在 `arch/arm/boot/dts/` 目录下：

```bash
ls /home/charliechen/imx-forge/out/linux/arch/arm/boot/dts/*.dtb
```

你应该能看到 `imx6ull-14x14-evk-emmc.dtb` 或类似的文件。

## 第四步：BusyBox Rootfs 构建——用户空间的基石

Rootfs 是内核启动后挂载的第一个文件系统，包含所有用户程序和配置。BusyBox 是一个集成了大量 UNIX 工具的单个可执行文件，非常适合嵌入式系统。

### 获取 BusyBox 源码

```bash
cd /home/charliechen/imx-forge
git submodule update --init --remote third_party/busybox
```

### 运行构建脚本

```bash
cd /home/charliechen/imx-forge
./scripts/build_helper/build-busybox.sh
```

### 脚本执行过程解析

#### 1. 依赖检查

```bash
[INFO] Checking host dependencies...
  ✓ build-essential
  ✓ make
  ✓ libncurses-dev
```

BusyBox 的依赖相对较少，只需要基本的构建工具。

#### 2. 工具链检查

```bash
[INFO] Checking toolchain...
Toolchain found: arm-none-linux-gnueabihf-gcc (GNU Toolchain for the Arm Architecture 15.2.Rel1) 15.2.1 20250409
Toolchain verified
```

#### 3. 配置 BusyBox

```bash
[INFO] Configuring BusyBox with defconfig...
make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/busybox defconfig
```

BusyBox 使用 `defconfig` 作为默认配置，包含了大部分常用命令。

#### 4. ARM 特定配置修复

```bash
[INFO] Checking ARM-incompatible config items...
  Disabled CONFIG_SHA1_HWACCEL (x86-only, not supported on ARM)
  Disabled CONFIG_SHA256_HWACCEL (x86-only, not supported on ARM)
```

BusyBox 的默认配置包含了一些 x86 特定的选项，在 ARM 上不支持。脚本会自动禁用这些选项。

**踩坑记录**：这个坑不容易发现。第一次编译时我没有禁用这些选项，编译过程看起来正常，但运行时某些命令会崩溃。排查好久才发现是硬件加速指令不支持。

#### 5. 编译 BusyBox

```bash
[INFO] Building BusyBox (8 parallel jobs)...
make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/busybox -j8
```

BusyBox 编译很快，通常 1-2 分钟就完成了。

#### 6. 安装 BusyBox

```bash
[INFO] Installing BusyBox to /home/charliechen/imx-forge/rootfs/nfs...
make -C third_party/busybox ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=/home/charliechen/imx-forge/out/busybox install CONFIG_PREFIX=/home/charliechen/imx-forge/rootfs/nfs
```

安装过程会在 `rootfs/nfs/` 目录下创建基本的目录结构和符号链接。

#### 7. 验证编译产物

```bash
[INFO] Verifying build artifacts...
  ✓ /home/charliechen/imx-forge/out/busybox/busybox: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 4.3.0, not stripped
    Size: 1258368 bytes
  ✓ /home/charliechen/imx-forge/out/busybox/.config: present
  ✓ /home/charliechen/imx-forge/rootfs/nfs/bin/busybox: installed
    Symlinks in bin/: 100+
```

关键产物说明：
- `busybox` 二进制文件，大约 1.2MB
- 100+ 个符号链接，指向 busybox 的不同命令

### 查看安装后的目录结构

```bash
tree -L 2 /home/charliechen/imx-forge/rootfs/nfs
```

输出类似：

```
/home/charliechen/imx-forge/rootfs/nfs
├── bin
│   ├── busybox
│   ├── sh -> busybox
│   ├── ls -> busybox
│   ├── cat -> busybox
│   ...
├── sbin
│   ├── init -> busybox
│   ...
├── usr
│   ├── bin
│   └── sbin
└── linuxrc -> bin/busybox
```

## 第五步：完善 Rootfs——让系统更完整

BusyBox 提供了基本命令，但一个可用的系统还需要更多的配置和库。

### 创建必要的目录和设备文件

```bash
cd /home/charliechen/imx-forge/rootfs/nfs

# 创建必要的目录
mkdir -p proc sys dev tmp etc lib mnt root var

# 创建设备文件
sudo mknod dev/console c 5 1
sudo mknod dev/null c 1 3
sudo mknod dev/zero c 1 5
sudo mknod dev/tty1 c 4 1
sudo mknod dev/ttymxc0 c 204 64
```

**经验**：`console` 和 `null` 设备是必须的，没有它们内核启动后无法打开控制台。

### 复制共享库

BusyBox 是动态链接的，需要复制工具链的共享库：

```bash
# 查看依赖
arm-none-linux-gnueabihf-readelf -d bin/busybox | grep NEEDED

# 复制库文件
mkdir -p lib
cp /opt/arm-gnu-toolchain/arm-none-linux-gnueabihf/libc/lib/* lib/
cp /opt/arm-gnu-toolchain/arm-none-linux-gnueabihf/libc/usr/lib/* usr/lib/ 2>/dev/null || true
```

**踩坑记录**：有一次我只复制了 `libc.so`，忘了 `libnss_*` 系列库，导致网络程序无法解析域名。用 `readelf` 查看依赖很重要。

### 创建 inittab 文件

`inittab` 是 BusyBox init 的配置文件，决定启动哪些进程：

```bash
cat > etc/inittab << 'EOF'
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty -L 115200 ttymxc0 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF
```

### 创建启动脚本

```bash
mkdir -p etc/init.d
cat > etc/init.d/rcS << 'EOF'
#!/bin/sh

# 挂载文件系统
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs none /tmp

# 配置网络
ifconfig eth0 up 2>/dev/null || true

# 欢迎信息
echo ""
echo "Welcome to IMX-Forge Linux!"
echo "Kernel: $(uname -a)"
echo ""

EOF
chmod +x etc/init.d/rcS
```

### 创建 passwd 和 group 文件

```bash
cat > etc/passwd << 'EOF'
root::0:0:root:/root:/bin/sh
EOF

cat > etc/group << 'EOF'
root:x:0:
EOF
```

### 创建 fstab 文件（可选）

如果需要挂载额外文件系统：

```bash
cat > etc/fstab << 'EOF'
proc      /proc   proc    defaults      0 0
sysfs     /sys    sysfs   defaults      0 0
tmpfs     /tmp    tmpfs   defaults      0 0
EOF
```

## 第六步：整合所有组件——打包成可烧录的镜像

现在我们已经有了所有组件：
- U-Boot：`out/uboot/u-boot-dtb.imx`
- Linux 内核：`out/linux/arch/arm/boot/zImage`
- 设备树：`out/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb`
- Rootfs：`rootfs/nfs/` 目录

### 方案一：SD 卡启动（推荐新手）

SD 卡启动最简单，适合开发和调试。

#### 1. 插入 SD 卡

```bash
# 查看 SD 卡设备
lsblk
```

假设 SD 卡是 `/dev/sdX`（X 是 a、b、c...），**请务必确认设备名，不要误删硬盘！**

#### 2. 分区和格式化

```bash
# 卸载所有分区
sudo umount /dev/sdX*

# 使用 fdisk 分区
sudo fdisk /dev/sdX
```

在 fdisk 交互界面：
```
o     # 创建新的 DOS 分区表
n     # 新建分区
p     # 主分区
1     # 分区号
      # 默认起始扇区
+100M # 分区大小 100MB（用于 boot）
t     # 修改分区类型
c     # W95 FAT32 (LBA)
n     # 新建分区
p     # 主分区
2     # 分区号
      # 默认起始扇区
      # 默认结束扇区（剩余所有空间）
w     # 写入分区表
```

#### 3. 格式化分区

```bash
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2
```

#### 4. 挂载分区

```bash
sudo mkdir -p /mnt/sdboot /mnt/sdroot
sudo mount /dev/sdX1 /mnt/sdboot
sudo mount /dev/sdX2 /mnt/sdroot
```

#### 5. 复制文件

```bash
# 复制内核和设备树到 boot 分区
sudo cp /home/charliechen/imx-forge/out/linux/arch/arm/boot/zImage /mnt/sdboot/
sudo cp /home/charliechen/imx-forge/out/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb /mnt/sdboot/

# 复制 rootfs 到 root 分区
sudo cp -r /home/charliechen/imx-forge/rootfs/nfs/* /mnt/sdroot/
sync
```

#### 6. 安装 U-Boot 到 SD 卡

```bash
# 烧录 U-Boot 到 SD 卡的引导区
sudo dd if=/home/charliechen/imx-forge/out/uboot/u-boot-dtb.imx of=/dev/sdX bs=1K seek=1 conv=notrunc
sync
```

**警告**：`dd` 命令很危险，确保设备名正确！`bs=1K seek=1` 跳过 SD 卡的第一个扇区（保留分区表），从第二个扇区开始写入。

#### 7. 卸载 SD 卡

```bash
sudo umount /mnt/sdboot /mnt/sdroot
```

### 方案二：eMMC 启动（生产环境）

eMMC 启动需要通过 U-Boot 命令操作，或者用专门的烧录工具。

#### 通过 U-Boot 烧录到 eMMC

1. 先用 SD 卡启动板子
2. 在 U-Boot 命令行执行：

```
=> mmc dev 1 0                    # 切换到 eMMC
=> mmc part 1                     # 查看 eMMC 分区
=> tftp 0x82000000 u-boot-dtb.imx # 下载 U-Boot
=> mmc write 0x82000000 0x2 0x800 # 写入 eMMC（偏移地址 1KB）
```

#### 通过 USB 烧录工具

NXP 提供了 `uuu` (Universal Update Utility) 工具，可以通过 USB 烧录：

```bash
sudo apt install libusb-1.0-0-dev
git clone https://github.com/NXPmicro/mfgtools
cd mfgtools
cmake . && make
sudo ./uuu u-boot-imx.imx
```

## 第七步：验证编译结果——确保每一步都正确

在烧录之前，我们最后验证一下各个组件。

### 验证 U-Boot

```bash
arm-none-linux-gnueabihf-readelf -h out/uboot/u-boot | grep -E "Machine:|Entry point"
```

输出应该类似：
```
Machine: ARM
Entry point address: 0x87800000
```

### 验证 Linux 内核

```bash
arm-none-linux-gnueabihf-readelf -h out/linux/vmlinux | grep -E "Machine:|Entry point"
```

输出应该类似：
```
Machine: ARM
Entry point address: 0x80008000
```

### 验证设备树

```bash
dtc -I dtb -O dts out/linux/arch/arm/boot/dts/imx6ull-14x14-evk-emmc.dtb | grep -E "model|compatible" | head -5
```

输出应该类似：
```
model = "Freescale i.MX6ULL 14x14 EVK Board";
compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
```

### 验证 BusyBox

```bash
file out/busybox/busybox
arm-none-linux-gnueabihf-readelf -d out/busybox/busybox | grep NEEDED
```

输出应该显示它是 ARM 架构的动态链接可执行文件，并列出依赖的库。

## 常见整合问题排查

### 问题 1：U-Boot 启动后卡住

**症状**：串口输出停在 U-Boot 的某个地方，没有继续启动内核。

**排查方法**：
1. 检查 `bootcmd` 环境变量是否正确
2. 检查内核镜像是否正确加载到内存
3. 检查设备树地址是否正确

**解决方法**：
```
=> printenv bootcmd
=> printenv bootargs
=> iminfo 0x82000000
```

### 问题 2：内核启动到一半崩溃

**症状**：看到一些内核输出，然后突然重启或停止。

**排查方法**：
1. 检查 `bootargs` 是否正确
2. 检查设备树是否匹配
3. 检查内存配置是否正确

**解决方法**：
```
=> setenv bootargs "console=ttymxc0,115200 root=/dev/mmcblk0p2 rootwait rw"
=> bootz 0x82000000 - 0x88000000
```

### 问题 3：Rootfs 挂载失败

**症状**：内核报错 "VFS: Cannot open root device"

**排查方法**：
1. 检查 `root=` 参数是否正确
2. 检查文件系统类型是否正确
3. 检查分区是否存在

**解决方法**：
```
=> mmc part
=> setenv bootargs "console=ttymxc0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait"
```

### 问题 4：无法登录

**症状**：看到 "Please press Enter" 但输入没反应。

**排查方法**：
1. 检查 inittab 配置
2. 检查 getty 程序是否存在
3. 检查串口设备是否正确

**解决方法**：
```
# 检查 inittab
cat etc/inittab
# 检查 tty 设备
ls -l dev/tty*
```

## 预告下一章

到这里，我们已经完成了所有组件的编译和整合。你手里应该有一张烧录好的 SD 卡，或者已经准备好通过网络启动的方式。

下一章，我们将真正把板子点起来！你会看到：
- U-Boot 启动日志的详细解读
- 内核启动过程的每个阶段
- Rootfs 挂载的验证方法
- 常见启动失败案例的分析
- 成功启动后的系统验证

准备好了吗？让我们见证系统启动的那一刻！
