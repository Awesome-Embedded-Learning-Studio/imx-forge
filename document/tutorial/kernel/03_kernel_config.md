---
title: 内核配置
---

# 从0开始配置Linux内核：menuconfig不是黑魔法，只是有点绕

## 为什么要写这篇配置教程

如果说编译内核是照着菜谱做菜，那配置内核就是自己设计菜谱。你选择哪些功能、不选哪些，直接决定了内核的大小、性能、功能。

但我第一次用menuconfig的时候，完全是懵的状态。几百个菜单项，每个还有子菜单，看得我头晕眼花。网上的教程要么太简单，只告诉你"选这个选那个"；要么太复杂，上来就讲Kconfig的语法规则。

我想做的是介于这两者之间：让你理解配置系统是怎么工作的，知道常用配置项的作用，并且能够创建自己的defconfig。到了最后，配置不再是"照抄别人"的机械过程，而是"知道自己在做什么"的理性选择。

## Kconfig系统：配置的底层逻辑

在进入menuconfig之前，先理解一下Kconfig系统的工作原理。Linux内核的配置系统叫Kconfig，它的核心思想是：

1. 用一种专门的语法（Kconfig语言）描述配置选项
2. 配置选项之间可以有依赖关系
3. 用户通过图形界面（menuconfig等）选择配置
4. 生成.config文件，供编译使用

Kconfig文件的格式是这样的：

```makefile
config DM9000
    tristate "DM9000 support"
    depends on NET_ETHERNET && ARM
    select CRC32
    help
      DM9000 ethernet driver

      To compile this driver as a module, choose M here.
      The module will be called dm9000.
```

这里解释一下各个字段的意思：

- `config DM9000`：定义一个配置选项，名字是CONFIG_DM9000
- `tristate`：三种状态（y/m/n），表示可以编译进内核(y)、编译成模块(m)、不编译(n)
- `depends on`：依赖关系，只有NET_ETHERNET和ARM都选了，这个选项才可选
- `select`：反向依赖，选中DM9000时自动选中CRC32
- `help`：帮助文本，在menuconfig里按?可以看到

tristate和bool的区别：tristate是三种状态（y/m/n），用于驱动（可以编译成模块）；bool是两种状态（y/n），用于核心功能（不能编译成模块）。

当你运行`make menuconfig`时，内核会扫描所有Kconfig文件，构建出一颗配置树，然后用ncurses库画出菜单界面。你选择配置项时，Kconfig系统会自动处理依赖关系——比如你选了某个功能，它依赖的其他选项会自动选中；你取消了某个功能，依赖它的选项会变灰或取消。

## defconfig到底是什么：默认配置的艺术

在02章我们提到了defconfig，现在来深入理解一下。

defconfig是"default configuration"的缩写，字面意思是"默认配置"。但这个"默认"不是内核默认，而是某个平台或板型的默认配置。对于i.MX6ULL，defconfig就是"适合i.MX6ULL的默认配置选择"。

defconfig文件位于`arch/arm/configs/`目录：

```bash
arch/arm/configs/
├── imx_aes_defconfig           # IMX-Forge 自定义配置（应用补丁后）
├── imx_v6_v7_defconfig         # NXP 官方：i.MX 6/7系列通用配置
├── imx_v7_defconfig            # NXP 官方：i.MX 7系列配置
├── multi_v7_defconfig          # NXP 官方：多平台v7配置
└── ...
```

> **注意：** `imx_aes_defconfig` 是 IMX-Forge 项目自定义的配置文件，需要先应用补丁才能使用。如果你直接使用 NXP 官方的 linux-imx 仓库，请使用 `imx_v7_defconfig` 或 `imx_v6_v7_defconfig`。

打开一个defconfig看看内容：

```makefile
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_NO_HZ=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_PREEMPT=y
CONFIG_ARM=y
CONFIG_ARCH_MXC=y
...
```

defconfig只记录与默认值不同的配置项。如果某个选项在Kconfig里默认是n，defconfig里设为y，那defconfig里会记录`CONFIG_XXX=y`；如果默认就是y，defconfig里就不会出现。

这样的设计有几个好处：

1. defconfig文件很小，只包含特定平台的特殊配置
2. Kconfig升级时（新增选项、改变默认值），defconfig仍然有效
3. 不同平台的defconfig可以共享，差异最小化

当你运行`make xxx_defconfig`时，内核做的事情是：

1. 读取Kconfig文件，建立完整的配置选项树
2. 应用指定的defconfig，覆盖部分默认值
3. 评估所有依赖关系，自动选中/取消相关选项
4. 生成完整的.config文件

所以.config是Kconfig默认值 + defconfig覆盖 + 依赖关系计算的结果，不是简单的复制。

## menuconfig实战：图形化配置教程

现在我们进入实战环节，打开menuconfig看看。

### 启动menuconfig

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux menuconfig
```

你应该看到类似这样的界面：

```
    *** User Mode Linux port ***
    General setup  --->
    [*] Enable loadable module support  --->
    *** Enable the block layer  --->
    System Type  --->
    Bus support  --->
    Kernel Features  --->
    Boot options  --->
    CPU Power Management  --->
    Floating point emulation  --->
    Userspace binary formats  --->
    Power management options  --->
    Networking support  --->
    Device Drivers  --->
    File systems  --->
    Kernel hacking  --->
    Security options  --->
    Cryptographic API  --->
    Library routines  --->
```

### 导航操作

menuconfig的操作按键如下：

- 方向键：移动光标
- Enter：进入子菜单或选中选项
- Esc Esc：返回上一级菜单
- Space：切换选项状态（y/n/m）
- /：搜索功能
- ?：查看帮助
- :q: 退出（会提示是否保存）

### 搜索功能

搜索功能非常实用，尤其当你不知道某个选项在哪的时候。按`/`，输入关键词：

```
  Search: DM9000
    Symbol: DM9000 [=n]
    Type  : tristate
    Prompt: DM9000 support
      Location:
        (1) -> Device Drivers
            -> Network device support (NETDEVICES [=y])
                -> Ethernet driver support (ETHERNET [=y])
    Defined at drivers/net/ethernet/davicom/Kconfig:6
      Depends on: NETDEVICES [=y] && ETHERNET [=y] && (ARM || MIPS)
      Selects: CRC32
```

搜索结果告诉你选项的位置、类型、依赖关系。你还可以按数字键跳转到该选项（需要支持跳转）。

### 常用菜单解析

我们来看看几个常用的菜单。

#### System Type：系统类型

这个菜单选择CPU和SoC类型：

```
System Type  --->
    [*] Support for ARM processor type
    ARM system type (NXP i.MX based)  --->
        ( ) Allwinner sunxi SoC
        ( ) Broadcom BCM2835
        (X) NXP i.MX based
        ...
    [*] MXC support
    [*] Support for i.MX6ULL
```

对于i.MX6ULL，确保选中"NXP i.MX based"和"Support for i.MX6ULL"。

#### Kernel Features：内核特性

这里配置内核的基本特性：

```
Kernel Features  --->
    Memory split (3G/1G user/kernel split)  --->
    (1) VMSPLIT_3G
    (2) VMSPLIT_2G
    (3) VMSPLIT_1G
    [*] High Memory Support
    [*] Tickless System (Dynamic Ticks)
    [*] High Resolution Timer Support
    Preemption Model (No Forced Preemption (Server))  --->
        (1) No Forced Preemption (Server)
        (2) Voluntary Kernel Preemption (Desktop)
        (3) Preemptible Kernel (Low-Latency Desktop)
```

- Memory split：用户空间和内核空间的虚拟内存划分。对于512MB内存的i.MX6ULL，3G/1G足够了
- Tickless System：动态时钟，省电
- Preemption Model：抢占模式。嵌入式系统选"Preemptible Kernel"可以获得更低延迟

#### Device Drivers：设备驱动

这是最大的菜单，包含了所有驱动：

```
Device Drivers  --->
    [*] Network device support  --->
        [*]   Ethernet driver support  --->
            [*]   DM9000 support
    [*] Character devices  --->
        [*]   Enable TTY
    [*] Serial drivers  --->
        [*]   IMX serial port support
    [*] I2C support  --->
        [*]   I2C device interface
    [*] SPI support  --->
    [*] MMC/SD/SDIO card support  --->
        [*]   MMC block device driver
```

这里根据你的硬件需求选择。i.MX6ULL开发板常用的驱动：
- 以太网：FEC或DM9000
- 串口：IMX serial port
- I2C：I2C device interface
- SPI：SPI support
- 存储：MMC/SD/SDIO card support

#### File systems：文件系统

选择要支持的文件系统：

```
File systems  --->
    [*] Second extended fs support (EXT2)
    [*] Ext3 journalling file system support
    [*] The Extended 4 (ext4) filesystem
    [*] Reiserfs support
    [*] Journalling Flash File System v2 (JFFS2) support
    [*] UBIFS file system support
    DOS/FAT/EXFAT/NT Filesystems  --->
        [*]   MSDOS fs support
        [*]   VFAT fs support
        [*]   exFAT fs support
```

对于嵌入式系统：
- EXT4用于SD卡或eMMC的普通分区
- UBIFS用于NAND Flash
- VFAT用于与Windows兼容的SD卡分区

### 保存和加载配置

修改完配置后，按Esc退到主菜单，选择"Save"保存：

```
    Do you wish to save your new configuration?
    <Save>
    <Exit>
```

选择<Save>，输入保存路径（默认是.output/linux/.config）。

你也可以把配置保存为另一个文件，以便后续使用。选择"Save configuration to an alternate file"，输入文件名。

下次要加载这个配置时，可以：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux loadcfg
# 或者在menuconfig里选择"Load configuration from an alternate file"
```

### 保存为defconfig

如果你想创建自己的defconfig，可以：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux savedefconfig
```

这会在输出目录生成`defconfig`文件，是当前配置的精简版本。你可以把它复制到`arch/arm/configs/`目录，作为新的defconfig：

```bash
cp out/linux/defconfig arch/arm/configs/my_imx6ull_defconfig
```

下次使用时：

```bash
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux my_imx6ull_defconfig
```

## 常用内核配置项说明

下面列出一些常用且重要的配置项，帮助你理解它们的含义。

### 系统基本信息

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_LOCALVERSION_AUTO | 自动添加版本信息（git commit hash） | y（调试） |
| CONFIG_LOCALVERSION="" | 自定义版本后缀 | 留空 |
| CONFIG_KERNEL_GZIP | 内核压缩方式（gzip） | y |
| CONFIG_KERNEL_XZ | 内核压缩方式（xz，更小但慢） | 可选 |

### 内存和进程

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_SMP | 对称多处理器支持 | y（多核） |
| CONFIG_NR_CPUS=2 | 最大CPU核心数 | 实际核心数 |
| CONFIG_VMSPLIT_3G | 3G用户/1G内核 | y（内存<1GB） |
| CONFIG_PREEMPT | 抢占式内核 | y（低延迟） |

### 网络相关

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_NET | 网络支持 | y |
| CONFIG_INET | TCP/IP协议栈 | y |
| CONFIG_NETFILTER | 防火墙/Netfilter | y（需要时） |
| CONFIG_VLAN_8021Q | VLAN支持 | 需要时 |
| CONFIG_BRIDGE | 网桥支持 | 需要时 |

### 驱动相关

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_SERIAL_IMX | i.MX串口驱动 | y |
| CONFIG_SERIAL_IMX_CONSOLE | 串口控制台 | y |
| CONFIG_FEC | i.MX以太网驱动 | y |
| CONFIG_DM9000 | DM9000以太网驱动 | 需要时 |
| CONFIG_I2C | I2C核心 | y |
| CONFIG_I2C_IMX | i.MX I2C驱动 | y |
| CONFIG_SPI | SPI核心 | y |
| CONFIG_SPI_IMX | i.MX SPI驱动 | y |
| CONFIG_MMC | MMC/SD核心 | y |
| CONFIG_MMC_SDHCI | SDHCI控制器 | 需要时 |
| CONFIG_MMC_SDHCI_ESDHC_IMX | i.MX ESDHC驱动 | y |

### 文件系统

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_EXT4_FS | EXT4文件系统 | y |
| CONFIG_VFAT_FS | VFAT文件系统 | y |
| CONFIG_FAT_FS | FAT文件系统 | y |
| CONFIG_NTFS_FS | NTFS文件系统（只读） | 需要时 |
| CONFIG_JFFS2_FS | JFFS2（NOR Flash） | 需要时 |
| CONFIG_UBIFS_FS | UBIFS（NAND Flash） | 需要时 |
| CONFIG_PROC_FS | proc伪文件系统 | y |
| CONFIG_SYSFS | sysfs伪文件系统 | y |

### 调试相关

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| CONFIG_DEBUG_KERNEL | 调试支持 | n（发布版） |
| CONFIG_DEBUG_INFO | 调试信息（-g） | y（调试） |
| CONFIG_MAGIC_SYSRQ | SysRq键 | y（调试） |
| CONFIG_KALLSYMS | 符号表 | y |
| CONFIG_PRINTK | printk输出 | y |

## 踩坑笔记：配置中的常见问题

在配置内核时，我踩过不少坑，这里分享几个最常见的。

### 问题1：模块加载失败

你编译了一个驱动为模块(m)，但加载时失败：

```bash
insmod: ERROR: could not insert module dm9000.ko: Unknown symbol
```

这通常是因为缺少依赖的模块或符号。检查一下：

```bash
modprobe --show-depends dm9000.ko
```

它会显示依赖关系，确保依赖的模块都加载了。

### 问题2：内核太大

你发现编译出来的zImage有10MB+，太大了。可能原因：

- 编译了太多驱动为y（应该编译为m，模块可以按需求加载，但是编进去了，裁剪可就难了）
- 开启了太多调试选项
- 没有精简不必要的功能

解决方法：使用menuconfig，把不需要的驱动设为m或n。

### 问题3：配置冲突

menuconfig里某个选项是灰色的，无法选择。这是因为依赖关系不满足。按`?`查看依赖：

```
  Symbol: FOO [=n]
  Type  : tristate
  Prompt: Foo support
    Defined at drivers/Kconfig:10
    Depends on: BAR && !BAZ
```

需要先选中BAR，取消BAZ。

### 问题4：.config被覆盖

你编辑了.config，但再次make时被覆盖。因为make会重新评估Kconfig依赖。

解决方法：
1. 修改defconfig，而不是直接改.config
2. 用`make oldconfig`更新.config而不是重新生成
3. 禁用CONFIG_IKCONFIG（内嵌配置）

## 实战：创建自己的defconfig

现在我们来创建一个适用于i.MX6ULL开发板的defconfig。

### 方法0：从官方配置创建项目配置（推荐新手）

IMX-Forge 项目的 `imx_aes_defconfig` 实际上就是这么创建的！它是基于 NXP 官方的 `imx_v7_defconfig`，**可选地**添加了 WiFi 固件支持。

#### 基础配置（适用于大多数情况）

如果你不需要 WiFi 功能，直接使用官方配置即可：

```bash
cd /path/to/imx-forge/third_party/linux-imx
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=../../out/linux imx_v7_defconfig
```

`imx_v7_defconfig` 已经包含了 i.MX6ULL 所需的所有基本配置。

#### 可选：添加 WiFi 固件支持（消除启动警告）

**为什么需要？** 如果你的板子使用 WiFi 模块，没有内置固件的话，内核启动时会显示类似这样的警告：

```
cfg80211: failed to load regulatory.db
```

这个警告不影响功能，但如果你想在内核中预装固件来消除警告，可以这样做：

```bash
# 1. 创建自定义配置（基于官方配置）
cd /path/to/imx-forge/third_party/linux-imx
cp arch/arm/configs/imx_v7_defconfig arch/arm/configs/my_imx6ull_defconfig

# 2. 添加固件配置（可选）
cat >> arch/arm/configs/my_imx6ull_defconfig << EOF
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"
CONFIG_EXTRA_FIRMWARE_DIR="/path/to/imx-forge/driver/firmwares"
EOF
```

**准备固件文件**（如果添加了上面的配置）：

```bash
# 创建固件目录
mkdir -p /path/to/imx-forge/driver/firmwares

# 克隆并生成无线监管数据库
cd /tmp
git clone https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git
cd wireless-regdb
make
cp regulatory.db* /path/to/imx-forge/driver/firmwares/
```

**验证配置**：

```bash
# 使用新配置
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=../../out/linux my_imx6ull_defconfig

# 检查配置（如果添加了固件配置）
grep "CONFIG_EXTRA_FIRMWARE" ../../out/linux/.config
```

#### 配置对比

```bash
# 官方配置（推荐用于大多数情况）
imx_v7_defconfig     600 行  ← 直接使用这个

# IMX-Forge 自定义配置（添加了 WiFi 固件）
imx_aes_defconfig    602 行  ← 可选，仅在需要消除 WiFi 警告时使用

# 差异仅 2 行：
# CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"
# CONFIG_EXTRA_FIRMWARE_DIR="..."
```

**建议**：大多数情况下，直接使用 `imx_v7_defconfig` 就足够了。只有在看到 WiFi 固件相关警告且想消除它时，才需要添加固件配置。

### 方法1：基于现有defconfig修改

最简单的方法是基于imx_aes_defconfig修改：

```bash
# 加载基础配置
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux imx_aes_defconfig

# 用menuconfig调整
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux menuconfig

# 保存为精简defconfig
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux savedefconfig

# 复制到源码目录
cp out/linux/defconfig arch/arm/configs/my_imx6ull_defconfig
```

### 方法2：从头创建

如果你想完全控制，可以：

```bash
# 清空配置
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux allnoconfig

# 用menuconfig逐步添加
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux menuconfig

# 保存defconfig
cp out/linux/.config arch/arm/configs/my_imx6ull_defconfig
```

### 方法3：脚本化配置

对于重复性配置，可以写一个脚本：

```bash
#!/bin/bash
# config_my_board.sh

make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux imx_aes_defconfig

# 使用scripts/config工具修改配置
./scripts/config --file out/linux/.config \
    --set-val CONFIG_LOCALVERSION "-myboard" \
    --disable CONFIG_DEBUG_KERNEL \
    --enable CONFIG_PREEMPT \
    --module CONFIG_DM9000

# 更新配置
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux olddefconfig

# 保存
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- O=out/linux savedefconfig
cp out/linux/defconfig arch/arm/configs/my_imx6ull_defconfig
```

## 配置优化建议

根据使用场景，给一些配置建议。

### 最小化配置（体积优先）

```makefile
# 不编译模块
CONFIG_MODULES=n

# 精简驱动
CONFIG_NETDEVICES=y
# 只选必需的网卡驱动

# 去掉调试
CONFIG_DEBUG_KERNEL=n
CONFIG_DEBUG_INFO=n
```

### 低延迟配置（实时性优先）

```makefile
# 抢占式内核
CONFIG_PREEMPT=y

# 高精度定时器
CONFIG_HIGH_RES_TIMERS=y

# 关闭节流
CONFIG_CPU_FREQ=n
```

### 调试配置（开发阶段）

```makefile
# 调试信息
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_KERNEL=y
CONFIG_MAGIC_SYSRQ=y

# 符号表
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# Oops定位
CONFIG_DEBUG_INFO=y
CONFIG_FRAME_POINTER=y
```

## 写在最后

到这里，Linux内核配置的核心内容你就掌握了。从Kconfig系统的原理，到menuconfig的使用，到常用配置项的含义，再到创建自己的defconfig，我们走完了配置的完整流程。

配置不是神秘的艺术，而是有规律可循的系统工程。理解了依赖关系、知道常用选项的作用、掌握了创建defconfig的方法，你就可以根据自己的需求定制内核了——无论是最小化体积、优化性能，还是增强调试能力，都在你的掌控之中。

下一篇文章，我们将进入内核模块的世界。你会看到：

- 什么是内核模块，为什么需要它
- 如何编写一个简单的内核模块
- 如何编译和加载模块
- 模块和驱动的区别

准备好了吗？我们来探索内核的动态扩展能力。

---

**延伸阅读**

- [Kconfig Language Documentation](https://www.kernel.org/doc/html/latest/kbuild/kconfig-language.html) - Kconfig语法文档
- [Linux Kernel Module Programming Guide](https://sysprog21.github.io/lkmpg/) - 内核模块编程指南
- [Kernel Newbies: Configuration](https://kernelnewbies.org/KernelBuildconfiguration) - 配置教程
