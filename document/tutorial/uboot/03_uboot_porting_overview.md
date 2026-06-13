---
title: 移植概览
---

# U-Boot完全移植概览：从官方源码到你的自制板，这条路有多远

## 依旧是首发的IMX6ULL移植2025UBoot分支教程

> 这个标题起的好大哦，但是实际上是笔者曾经的UBoot教程的一个巨大的翻新版本，我才发现曾经的教程在UBoot上就存在不少的错误，这里进行统一的更正！

## 写在前面的话

笔者就写过给正点原子开发板的移植教程, 那个时候还年轻，自己激昂的搞了一通成功换掉了正点原子老旧的UBoot的教程，古战场的遗址在:

👉: https://blog.csdn.net/charlie114514191/article/details/147116372

UBoot是我们的起点，对于现代UBoot，移植好了它，我们就完成了绝大部分的工作了。不得不承认，NXP的文档有点难以企及（对我这种半吊子爱好者）。网上的教程版本五花八门，正点原子的教程是基于他们自己的板子改的，你跟着敲一遍发现你的板子就是起不来。最要命的是，你不知道问题出在哪里——是设备树写错了？是DDR初始化参数不对？还是编译配置选错了？怎么一起来秒炸啊我靠。

这篇文章就是写给那个时候的我的。我们不讲虚的，直接从源码开始，一步步走完整个移植流程。你会明白每个步骤为什么要这么做，哪个文件是干什么的，出了问题该从哪里查。当你读完这篇文章，你会发现U-Boot移植其实没有那么神秘，它就是一个工程问题，有清晰的步骤可循。

但先别急，在开始动刀子之前，我们需要先把整个图景搞清楚。

## NXP官方分支 vs Mainline：我们到底该用哪个

UBoot不是NXP的专属，实际上，人家有名字的：Universary-Boot。非常牛逼的名字，就是通用引导。每个做i.MX移植的人都会问的第一个问题——U-Boot有两个主要的代码仓库：一个是NXP维护的`uboot-imx`分支，另一个是U-Boot官方的mainline仓库。该选哪个？

简单来说：**如果你用的是i.MX6ULL/i.MX8这类NXP芯片，而且没有那么大的热情做MainLine维护。老实用NXP分支，别搞什么追求主线最新版（真的兄弟们）**。

为什么这么说？让我给你讲清楚。

NXP的`uboot-imx`分支虽然版本号看起来老一些（我们用的是lf_v2025.04，对应mainline的v2025.04），但它包含了所有i.MX芯片需要的支持：
- IVT镜像生成工具完整支持，tools/mkimage直接生成imx格式的镜像
- DCD DDR初始化参数已经帮你配好了，board/freescale/mx6ullevk/imximage.cfg里都有
- 各种NXP专有的外设驱动（比如HAB安全启动、DCP加密引擎）都已经集成
- 针对i.MX优化的启动流程，包括SPL支持和 Falcon Mode快速启动

所以我们的选型很明确：**基于NXP的uboot-imx分支，长期跟踪上游更新，但坚决不乱切版本**。lf_v2025.04这个版本是经过验证的稳定版，i.MX6ULL的支持已经很成熟了，没必要去追v2025.10或者v2026.01这种最新版。记住，做嵌入式产品，稳定比新功能重要一万倍。

## U-Boot移植的整体流程：从源码到可烧录镜像

好了，选定了分支，接下来我们看看整个移植流程长什么样。我先给你一个整体的概念，然后我们再深入到每个细节。

```
┌─────────────────────────────────────────────────────────────────────┐
│                        U-Boot移植整体流程                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. 源码准备阶段                                                     │
│     ├─ 克隆NXP uboot-imx仓库                                         │
│     ├─ 检出lf_v2025.04分支                                          │
│     └─ 确认工具链版本（arm-linux-gnueabihf-）                       │
│                                                                     │
│  2. 配置选择阶段                                                     │
│     ├─ 从configs/找到最接近的参考defconfig                          │
│     ├─ 复制并重命名为你的板子名                                       │
│     └─ 通过make menuconfig调整配置                                  │
│                                                                     │
│  3. 设备树移植阶段                                                   │
│     ├─ 复制参考板DTS文件                                            │
│     ├─ 修改compatible和model属性                                     │
│     ├─ 根据你的原理图调整pinctrl、外设节点                            │
│     └─ 添加u-boot特有配置（*-u-boot.dtsi）                          │
│                                                                     │
│  4. 板级代码移植阶段                                                 │
│     ├─ 在board/创建你的板子目录                                      │
│     ├─ 编写Kconfig和MAINTAINERS                                     │
│     ├─ 复制并修改imximage.cfg（DCD配置）                            │
│     └─ 编写板级初始化代码（如果需要特殊逻辑）                          │
│                                                                     │
│  5. 头文件配置阶段                                                   │
│     ├─ 在include/configs/创建板级头文件                              │
│     ├─ 定义内存布局、环境变量配置                                    │
│     └─ 引用公共配置头文件                                            │
│                                                                     │
│  6. 编译验证阶段                                                     │
│     ├─ make defconfig加载配置                                        │
│     ├─ make -j$(nproc)编译                                           │
│     ├─ 检查生成的u-boot.bin、u-boot.imx                             │
│     └─ 用imxdownload或者UUU工具烧录验证                              │
│                                                                     │
│  7. 调试迭代阶段                                                     │
│     └─ 根据串口输出反复调整直到正常启动                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

这个流程看起来有点长，但别被吓到了。其实大部分情况下，你的板子和官方EVK差别不大，主要工作集中在设备树调整上。板级代码和头文件基本上可以照搬，改几个关键参数就行了。

接下来我们按照这个流程，一步步看每个阶段具体要做什么。

### 源码准备阶段：第一步就走对

首先你得拿到源码。直接去NXP的GitHub仓库clone：

```bash
git clone https://github.com/nxp-imx/uboot-imx.git
cd uboot-imx
git checkout lf_v2025.04
```

这里有个坑要注意：NXP的仓库有好几个分支，lf_v2025.04、rel_imx_5.4.70_2.3.0之类的，看着眼花缭乱。记住，我们选的是lf_开头的分支，这是Linaro维护的相对更新的版本。rel_开头的是NXP BSP里带的版本，通常比较老。

checkout完了之后，先确认一下工具链。U-Boot编译需要ARM交叉编译工具链，我们用的是arm-none-linux-gnueabihf-gcc。你可以用这个命令检查：

```bash
arm-none-linux-gnueabihf-gcc --version
```

虽然有一说一，只要保证架构大差不差，一般而言不太可能出问题，但是就怕万一对不对。笔者是爱好者，不做产品，那就梭哈最新的直接干：

```
❯ arm-none-linux-gnueabihf-gcc -v
Using built-in specs.
COLLECT_GCC=arm-none-linux-gnueabihf-gcc
COLLECT_LTO_WRAPPER=/opt/arm-gnu-toolchain/bin/../libexec/gcc/arm-none-linux-gnueabihf/15.2.1/lto-wrapper
Target: arm-none-linux-gnueabihf
Configured with: /tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/src/gcc/configure --target=arm-none-linux-gnueabihf --prefix= --with-sysroot=/arm-none-linux-gnueabihf/libc --with-build-sysroot=/tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/build-arm-none-linux-gnueabihf/install//arm-none-linux-gnueabihf/libc --with-bugurl=https://gitlab.arm.com/tooling/gnu-devtools-for-arm/-/issues/ --enable-gnu-indirect-function --enable-shared --disable-libssp --disable-libmudflap --enable-checking=release --enable-languages=c,c++,fortran --with-gmp=/tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/build-arm-none-linux-gnueabihf/host-tools --with-mpfr=/tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/build-arm-none-linux-gnueabihf/host-tools --with-mpc=/tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/build-arm-none-linux-gnueabihf/host-tools --with-isl=/tmp/jenkins-1e1af46f/workspace/GNU-toolchain/arm-15/build-arm-none-linux-gnueabihf/host-tools --with-arch=armv7-a --with-fpu=neon --with-float=hard --with-mode=thumb --with-arch=armv7-a --with-pkgversion='Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)'
Thread model: posix
Supported LTO compression algorithms: zlib zstd
gcc version 15.2.1 20251203 (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 
```
这是今年2月份刚出的

### 配置选择阶段：找个靠谱的起点

接下来是选一个defconfig作为起点。configs/目录里有500多个配置文件，怎么选？

原则很简单：**找芯片相同、外设最接近的板子**。

对于i.MX6ULL，你有这些选择：
- `mx6ull_14x14_evk_defconfig`：14x14 EVK标准版，SD卡启动
- `mx6ull_14x14_evk_emmc_defconfig`：eMMC版本，如果你的板子用eMMC就选这个
- `mx6ull_9x9_evk_defconfig`：9x9 EVK版本

正点原子的Alpha板子和14x14 EVK很像，外设配置基本一致，所以可以直接用`mx6ull_14x14_evk_emmc_defconfig`作为起点。复制一份改名叫你的板子名：

```bash
cp configs/mx6ull_14x14_evk_emmc_defconfig configs/mx6ull_myboard_defconfig
```

然后打开这个文件，你会看到一堆CONFIG_开头的配置项。这里有个很重要的配置：

```
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-14x14-evk"
```

这个就是指定设备树文件名的，改成你的设备树文件名：

```
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-myboard"
```

还有个CONFIG_TARGET选项，指定目标板子：

```
CONFIG_TARGET_MX6ULL_14X14_EVK=y
```

这个需要你在board/和Kconfig里添加你自己的板子定义才能改成你的板子名。不过刚开始可以先用EVK的，后面再改。

### 设备树移植阶段：这是最核心的部分

设备树是U-Boot移植最关键的部分，也是你花时间最多的地方。整个移植过程，80%的工作量都在这里。

首先理解一下设备树的结构。U-Boot的设备树和Linux内核的设备树基本兼容，但有一些U-Boot特有的属性。设备树文件通常分为几个层次：

1. `.dtsi`文件：设备树include文件，描述通用的硬件结构
2. `.dts`文件：具体的板级设备树，include .dtsi文件，然后做修改
3. `*-u-boot.dtsi`文件：U-Boot专用的设备树配置

对于i.MX6ULL，设备树结构是这样的：
- `imx6ull.dtsi`：i.MX6ULL芯片的基础设备树，描述CPU、时钟、中断控制器这些
- `imx6ull-14x14-evk.dts`：14x14 EVK的板级设备树
- `imx6ull-14x14-evk-u-boot.dtsi`：U-Boot专用的EVK配置

你需要复制这些文件，然后根据你的硬件修改。具体怎么做，我们下一章会详细讲。这里先给你一个大概的概念：

首先复制板级DTS：

```bash
cp arch/arm/dts/imx6ull-14x14-evk.dts arch/arm/dts/imx6ull-myboard.dts
cp arch/arm/dts/imx6ull-14x14-evk-u-boot.dtsi arch/arm/dts/imx6ull-myboard-u-boot.dtsi
```

然后打开DTS文件，修改model和compatible属性：

```dts
/ {
    model = "My Company i.MX6ULL My Board";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};
```

compatible这里先用EVK的兼容字符串，因为U-Boot的板级代码是靠这个匹配的。等你创建了独立的板级配置，再改成你自己的。

接下来就是根据你的原理图，逐个调整外设节点。这部分工作很琐碎，但很重要。每个外设的配置通常包括几个部分：

- `status`属性：设置为"okay"启用，"disabled"禁用
- `pinctrl`属性：指定引脚配置
- `clock`属性：指定时钟
- 其他外设特定的属性（比如I2C地址、GPIO、中断号等）

比如UART的配置：

```dts
&uart1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart1>;
    status = "okay";
};
```

pinctrl_uart1的定义通常在.dtsi文件里：

```dts
pinctrl_uart1: uart1grp {
    fsl,pins = <
        MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
        MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
    >;
};
```

这里的MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX是NXP定义的宏，表示UART1_TX引脚配置为UART1_DCE_TX功能。0x1b0b1是pad配置参数，定义了上下拉、驱动强度等。

每个外设都要这么配置，你需要对照原理图，确认每个引脚的配置是否正确。这部分工作很繁琐，但别偷懒，错了排查起来更麻烦。

### 板级代码移植阶段：大部分情况可以跳过

设备树普及之后，板级代码的作用已经大大弱化了。对于i.MX6ULL，大部分情况下你不需要写板级代码，直接用EVK的就行。

但有些特殊情况还是需要板级代码的：

1. 你的板子有特殊的初始化逻辑（比如特殊的电源管理芯片）
2. 你用的DDR型号和EVK不一样，需要调整DDR初始化参数
3. 你需要添加一些U-Boot命令

对于这些情况，你需要在board/freescale/下创建你自己的板子目录：

```bash
cp -r board/freescale/mx6ullevk board/freescale/myboard
cd board/freescale/myboard
mv mx6ullevk.c myboard.c
mv Kconfig myboard.Kconfig
```

然后修改这些文件里的内容，把所有mx6ullevk改成myboard。Kconfig文件是Kconfig配置系统的定义，告诉构建系统你的板子存在。

imximage.cfg文件很重要，它定义了IVT镜像格式和DCD DDR初始化参数：

```
IMAGE_VERSION 2

BOOT_FROM sd

DATA 4 0x020c4068 0xffffffff
...
```

这里的DATA行就是DCD配置，定义了DDR控制器的寄存器值。如果你用的DDR型号和EVK不一样，这里需要调整。这个参数怎么来？通常从DDR厂商的Datasheet或者参考设计里获取，或者让硬件工程师提供。

### 头文件配置阶段：主要是环境变量

include/configs/目录下是板级头文件，主要是定义一些编译时配置和环境变量。

板级头文件的作用正在减弱，因为很多配置都移到defconfig了。但还是有一些配置需要在头文件里定义：

- 内存布局（DRAM基地址、大小）
- 默认环境变量（bootargs、bootcmd）
- 一些遗留的配置开关

对于i.MX6ULL，你可以直接复制EVK的头文件：

```bash
cp include/configs/mx6ullevk.h include/configs/myboard.h
```

然后修改里面的内容。主要是环境变量部分，这部分在下一章会详细讲。

环境变量是U-Boot的"配置文件"，定义了启动参数、boot命令、网络配置等。默认环境变量在头文件里定义，但你也可以在运行时修改并保存到存储介质。

典型的环境变量定义：

```c
#define CFG_EXTRA_ENV_SETTINGS \
    "script=boot.scr\0" \
    "image=zImage\0" \
    "console=ttymxc0\0" \
    "fdt_addr=0x83000000\0" \
    "bootargs=console=${console},${baudrate} root=/dev/mmcblk1p2 rootwait rw\0" \
    "bootcmd=run loadbootscript; run bootscript\0" \
```

这里\0是字符串分隔符，U-Boot的环境变量解析器用它来分隔多个变量。

### 编译验证阶段：见证奇迹的时刻

配置好了，开始编译。编译过程很简单：

```bash
make mx6ull_myboard_defconfig
make -j$(nproc)
```

编译过程会产生很多输出，最后你会看到几个关键文件：

- `u-boot`：ELF格式的U-Boot，带调试符号
- `u-boot.bin`：纯二进制格式，可以直接烧录（但没有IVT头）
- `u-boot.imx`：NXP i.MX格式的镜像，包含IVT头，可以直接烧录

对于i.MX6ULL，你应该用u-boot.imx。这个文件已经包含了IVT头和DCD数据，ROM Code可以直接识别并加载。

烧录工具有几种选择：
- NXP的UUU工具：官方工具，支持USB烧录，功能强大
- imxdownload：社区工具，通过串口烧录，简单易用
- dd命令：直接写到SD卡，适合eMMC/SD卡启动

我是直接imxdownload了，UUU没用过，哈哈哈（正点原子的，致敬左神）

### 调试迭代阶段：排查问题的艺术

编译烧录完了，接上串口，上电，你会看到U-Boot的启动日志。如果一切顺利，你会看到类似这样的输出：

```
U-Boot 2025.04-xxxx (Mar 13 2026 - 10:30:00 +0800)

CPU:   Freescale i.MX6ULL rev1.1 528 MHz
Reset cause: POR
Model: My Company i.MX6ULL My Board
Board: MX6ULL 14x14 EVK
DRAM:  512 MiB
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
Loading Environment from MMC... OK
In:    serial
Out:   serial
Err:   serial
Net:   eth0: ethernet@02188000
Fastboot: Normal
Normal Boot
Hit any key to stop autoboot
```

如果看到这个，恭喜你，U-Boot移植成功了！

但大多数时候，你不会这么顺利。可能会有各种各样的问题：

- 串口没有任何输出：可能是引脚配置错了，或者波特率不对
- 启动到一半死机：可能是DDR初始化有问题，或者设备树配置错误
- 环境变量加载失败：可能是存储介质配置有问题
- 网络不通：可能是PHY芯片型号不对，或者引脚配置错了

这时候就需要耐心排查。U-Boot的好处是它有详细的调试输出，你可以打开DEBUG选项获取更多信息。下一章我们会详细讲各种常见问题的排查方法。

## 源码目录结构：东西都放在哪

当你第一次看U-Boot源码，打开目录一看——好家伙，几十个文件夹，不知道从哪下手。其实核心目录就那么几个，其他的都是辅助性的。我给你按重要性排个序：

### 第一优先级：移植必须关注的目录

`arch/arm/dts/` —— **这是你花时间最多的地方**

这里存放ARM架构的设备树源文件。i.MX6ULL相关的所有DTS都在这里。你用ls命令看一下：

```bash
ls arch/arm/dts/imx6ull*
```

你会看到：
- `imx6ull.dtsi`：i.MX6ULL芯片的基础设备树，描述CPU、时钟、中断控制器这些芯片内部的东西
- `imx6ull-14x14-evk.dts`：NXP官方14x14 EVK板子的完整设备树
- `imx6ull-14x14-evk-u-boot.dtsi`：U-Boot专用的设备树配置
- `imx6ull-9x9-evk.dts`：9x9 EVK版本
- 可能还有其他厂商的板子，比如`imx6ull-colibri.dts`

这些文件都是你的参考。你需要复制这些文件，改名为你的板子名，然后根据你的硬件修改。

设备树文件的组织有个规律：.dtsi文件是include文件，描述通用的硬件结构；.dts文件是具体的板级配置，include .dtsi文件，然后做板级特定的修改。*-u-boot.dtsi文件是U-Boot专用的配置，不会被Linux内核使用。

`configs/` —— **编译配置的入口**

这里放着500多个defconfig文件，每个对应一个板型的编译配置。你用ls命令grep一下i.MX6ULL相关的：

```bash
ls configs/ | grep mx6ull
```

你会看到：
- `mx6ull_14x14_evk_defconfig`：14x14 EVK的默认配置
- `mx6ull_14x14_evk_emmc_defconfig`：eMMC版本的配置
- `mx6ull_14x14_evk_nand_defconfig`：NAND版本的配置
- `mx6ull_9x9_evk_defconfig`：9x9 EVK版本
- `mx6ull_aes_emmc_defconfig`：这个是有人加了AES板子的配置

defconfig文件的格式是Kconfig格式，其实就是一系列CONFIG_选项的赋值。你可以用`make menuconfig`图形界面修改，也可以直接编辑文件。

对于i.MX6ULL移植，你需要复制一个最接近你的板子的defconfig，改名后作为起点。如果你用eMMC，就复制emmc版本；如果用SD卡，就复制普通版本。

`board/freescale/` —— **板级初始化代码**

这里存放各个板子的板级支持包。对于i.MX6ULL，主要看`mx6ullevk/`目录：

```bash
ls board/freescale/mx6ullevk/
```

你会看到：
- `mx6ullevk.c`：板级初始化C代码，大部分情况下不需要改
- `imximage.cfg`：IVT镜像配置文件，包含DCD DDR初始化参数，这个很重要
- `imximage_lpddr2.cfg`：LPDDR2版本的配置
- `plugin.S`：DDR初始化插件代码
- `Kconfig`：Kconfig配置定义
- `MAINTAINERS`：维护者信息

mx6ullevk.c文件很小，因为大部分逻辑都在设备树里了。它主要包含board_early_init_f()和board_init()这些函数，做一些板级特定的初始化。

imximage.cfg文件很重要，它定义了IVT镜像格式和DCD数据。IVT（Image Vector Table）是NXP芯片启动时需要的特殊格式，DCD（Device Configuration Data）是DDR初始化参数。如果你的DDR型号和EVK不一样，这里需要调整。

`include/configs/` —— **板级头文件**

存放每个板子的配置头文件，主要定义内存布局、环境变量配置等：

```bash
ls include/configs/ | grep mx6ull
```

你会看到：
- `mx6ullevk.h`：14x14 EVK的头文件
- 可能还有其他板子的头文件

板级头文件的作用正在减弱，因为很多配置都移到defconfig了。但还是有一些配置需要在头文件里定义，比如环境变量默认值。

对于i.MX6ULL移植，你可以直接复制EVK的头文件，然后修改环境变量部分。

### 第二优先级：了解即可，移植一般不需要改

`arch/arm/cpu/` —— **CPU相关底层代码**

`arch/arm/cpu/armv7/`是ARMv7架构的通用代码，`mach-imx/`是i.MX系列专用代码。这里面的代码已经很成熟了，除非你要做很底层的修改，否则别动它。

这里面有几个关键文件：
- `start.S`：U-Boot的入口点，汇编代码
- `lowlevel_init.S`：底层初始化
- `cpu.c`：CPU初始化C代码

这些代码是U-Boot启动的核心，但已经很稳定了，没必要改。

`arch/arm/lib/` —— **ARM架构通用库函数**

启动流程相关的汇编和C代码，比如lowlevel_init、board_init_f这些。很关键，但一般情况下不需要你改。

这里面有：
- `crt0.S`：C运行时环境初始化
- `relocate.S`：代码重定位
- `cache.S`：缓存操作

这些是底层启动代码，改错了启动不了。

`drivers/` —— **驱动代码**

按外设类型分类：`mmc/`是eMMC/SD卡驱动，`net/`是以太网驱动，`gpio/`是GPIO，`i2c/`、`spi/`顾名思义。NXP已经把i.MX6ULL的驱动都写好了，除非你要加很特殊的外设，否则不用动。

`cmd/` —— **U-Boot命令实现**

U-Boot命令行里的命令（boot、md、mw、dhcp、tftp）都在这。如果你要添加自定义命令，在这里加。

比如你想添加一个hello命令，需要完成以下步骤：

**第一步：创建hello.c文件**

在`cmd/`目录下创建`hello.c`文件：

```c
#include <command.h>
#include <stdio.h>

static int do_hello(struct cmd_tbl *cmdtp, int flag, int argc,
                   char *const argv[])
{
    printf("Hello World!\n");
    return 0;
}

U_BOOT_CMD(
    hello, 1, 1, do_hello,
    "print hello message",
    ""
);
```

> **注意**：在U-Boot 2025.04等新版本中，`<common.h>`头文件已经不可用，正确的头文件是`<command.h>`和`<stdio.h>`。如果使用旧的头文件会导致编译失败。

**第二步：修改cmd/Makefile**

仅将hello.c放入cmd/目录并不会自动参与编译，还需要在`cmd/Makefile`中显式添加。打开`cmd/Makefile`文件，在适当位置添加：

```makefile
obj-y += hello.o
```

或者更规范的方式（如果命令支持配置选项）：

```makefile
obj-$(CONFIG_CMD_HELLO) += hello.o
```

**第三步：重新编译**

```bash
make -j$(nproc)
```

编译完成后，U-Boot就有hello命令了。

> **重要提示**：如果不修改Makefile，即使hello.c文件存在，也不会生成对应的目标文件，命令不会出现在U-Boot命令列表中。这是初学者容易遇到的常见问题。

`common/` —— **通用功能代码**

环境变量处理、设备初始化、启动流程这些。核心代码，但不用你改。

`scripts/` —— **构建脚本和工具**

Kconfig配置系统、编译检查脚本、还有一些辅助工具。其中`scripts/kconfig/`是Kconfig系统，支持`make menuconfig`。

`tools/` —— **宿主机工具**

`mkimage`这个生成IVT镜像的关键工具就在这里。编译完成后会在`tools/`目录生成各种辅助工具。

### 第三优先级：基本不需要关心

`api/` —— 给其他程序调用U-Boot功能的API，基本用不到
`disk/` —— 磁盘分区相关代码
`doc/` —— 文档，写得像技术规范书，可读性一般
`env/` —— 环境变量实现
`examples/` —— 示例代码
`fs/` —— 文件系统支持（FAT、EXT4、UBIFS）
`lib/` —— 通用库函数
`net/` —— 网络协议栈
`post/` —— 上电自检相关
`test/` —— 单元测试

## 我们项目的技术选型：为什么是lf_v2025.04

现在我们来聊聊为什么我们的项目选择了lf_v2025.04这个具体版本。

首先说版本号规则。U-Boot从2008年开始改用基于时间的版本号，格式是`vYYYY.MM`，比如v2025.04就是2025年4月发布的版本。NXP的uboot-imx仓库会在U-Boot官方发布的基础上，加上i.MX系列的补丁，然后打上`lf_`前缀（lf代表Linaro和Freescale的合作）。

U-Boot采用固定的三个月发布周期，非常可预测。发布后约21天是合并窗口，之后进入RC阶段主要修复bug。最新版本是2026年1月5日发布的v2026.01，往前是v2025.10、v2025.07、v2025.04——我们的项目就是基于v2025.04的NXP分支。

选择lf_v2025.04是基于几个实际的考虑：

**稳定性考虑**：这个版本发布已经有一段时间了（我们现在2026年3月），社区里已经有不少人在用，潜在的bug已经被发现和修复了。i.MX6ULL是成熟的芯片，这个版本对它的支持已经非常稳定。如果你追求最新版本，可能会遇到一些新引入的bug，而这些问题在社区里还没有解决方案。

**功能完整性**：v2025.04包含了我们需要的关键功能：
- 完整的DM（Driver Model）驱动框架支持。DM是U-Boot从2015年开始引入的新驱动框架，现在已经成为标准。老版本U-Boot还在用老的驱动模型，代码结构不统一，维护困难。
- 设备树支持成熟，不需要维护老旧的板级代码。在DM和设备树普及之前，每个板子都要写大量的板级代码，硬件改动就要改代码重新编译。现在大部分硬件描述都移到设备树了，换硬件只需要改DTS。
- eMMC/SD卡、网络、USB这些基础外设驱动齐全。i.MX6ULL的驱动都已经很成熟了，基本开箱即用。
- Fastboot、UUU烧录工具支持完整。NXP的UUU工具很强大，支持USB烧录、自动识别芯片类型、批量烧录等功能，对产品量产很有帮助。
- SPL（Secondary Program Loader）支持，可以从不同介质启动。SPL是一个精简版的U-Boot，负责初始化DDR和加载主U-Boot。对于i.MX6ULL，SPL可以支持从SD卡、eMMC、NAND Flash、SPI NOR Flash等多种介质启动。

**工具链兼容性**：这个版本和当前主流的ARM GCC工具链兼容性很好。我们用的是arm-linux-gnueabihf-gcc，版本在10.x或者11.x都没问题。太老的U-Boot版本可能对新版工具链有兼容问题，比如用了一些GCC扩展特性在新版GCC中被废弃了，或者链接脚本格式不兼容。

**长期维护考虑**：选择一个已经稳定一段落的版本，意味着未来几年内都不会有大的兼容性问题。如果每次U-Boot更新都要跟着改代码，那维护成本就太高了。对于产品项目来说，稳定性远比新功能重要。

当然，版本选择也是个权衡。lf_v2025.04不是最新的，如果你需要一些很新的功能（比如对某个新型号外设的支持），可能需要考虑更新版本。但对于i.MX6ULL这种成熟芯片，稳定压倒一切。

## 与正点原子的方案对比：我们的优势

说到i.MX6ULL的U-Boot移植，绕不开的就是正点原子的教程。他们的Alpha开发板确实做得不错，教程也详细，但我们为什么不直接用他们的方案，而要自己搞一套呢？

让我给你分析一下两者的区别：

**版本差异**：正点原子的U-Boot版本相对较老（2016年左右的版本，不知道有没有更新以下哈哈），用的是NXP的老 BSP。我们的方案基于lf_v2025.04，晚了五六年。这五六年里U-Boot的改进是巨大的：驱动模型（Driver Model）完全成熟，设备树支持更完善，代码结构更清晰。老版本有很多已经废弃的API和配置方式，维护起来很痛苦。比如老版本U-Boot用CONFIG_SYS_XXX的宏定义来配置硬件，新版本都移到设备树了；老版本用老的驱动框架，新版本用DM。这些差异会让你的代码和社区脱节，以后想升级会很困难。

**代码组织**：正点原子的方案把很多配置硬编码在代码里，设备和板子强耦合。你想换个存储介质？对不起，改代码重新编译。他们的教程里有很多地方直接修改源码，而不是通过配置系统。这样做的后果是你的代码变成"魔改版"，和官方源码差异巨大，以后想合并官方更新几乎不可能。我们的方案充分利用设备树，硬件描述和代码分离，换存储、改外设只需要改DTS，不用动核心代码。这样你的代码可以保持和官方源码的同步，将来U-Boot更新了，你可以很容易地合并。

**补丁管理**：正点原子的修改是直接在源码上改的，你很难分清楚哪些是官方原版，哪些是他们改的。他们的教程通常是"打开文件xxx，找到行yyy，改成zzz"这种操作，改完之后你不知道改了什么，为什么这么改。我们的方案用Git format-patch生成的标准补丁文件，打上`[uboot-imx]`标签，清晰可追溯。每个补丁都是完整的修改记录，有作者、日期、提交信息，将来U-Boot更新了，我们可以很容易地检查补丁是否还能干净地打上去。

**板卡适配性**：正点原子的方案是为他们自己的板子优化的，你要用到自制板子上，改起来不比从零开始容易多少。他们的板子有自己独特的外设配置，比如特殊的LCD屏、特殊的网络PHY等。你要把这些改成你自己的，工作量不小。我们的方案从一开始就考虑了多板卡支持，通过BOARD.yaml描述板卡差异，补丁按板卡分类，接入新板子只需要添加对应的板卡配置和设备树。我们的目标是让你能够快速适配到自己的板子，而不是被绑定在某个特定板子上。

**长期维护**：正点原子的方案更新频率不高，很多新的功能特性不会及时跟进。他们的教程可能几年不更新，等你遇到新问题，教程里没有解决方案。我们的项目是开源的，社区可以一起贡献，补丁管理规范，长期维护更容易。你可以提交PR，我们一起改进。

当然，正点原子的方案也有它的优势：对于初学者，他们的"跟着做就能用"的教程确实更容易上手。如果你只是想快速跑通一个demo，不关心底层原理，那正点原子的方案确实更直接。但我们的定位是给那些想真正理解U-Boot、想维护自己产品的人，而不仅仅是做一个实验。你花时间理解了这套方案，将来换芯片、换板子，都能快速适配。

## 接下来的路

到这里，你应该对U-Boot移植的整体图景有了一个清晰的认识。我们讲了为什么选择NXP分支而不是mainline，讲了从源码到镜像的完整流程，讲了每个目录的作用，讲了我们的技术选型和与正点原子方案的对比。

但这些还只是"概览"。下一篇文章，我们会真正开始动手，从零移植一个U-Boot到我们的板子上。你会看到如何从官方EVK的DTS开始，一步步改成适合你的板子的设备树；如何创建你自己的板级配置；如何编译、烧录、调试；出了问题该怎么排查。

在下一章，我们会做一件真正有意义的事情：从NXP官方的EVK配置开始，一步步改造成适合正点原子Alpha板子的配置。这个过程中，你会学到如何分析原理图、如何修改设备树、如何配置启动参数、如何排查问题。

准备好了吗？这条路不会太容易，但走完之后，你会对U-Boot、对嵌入式系统启动流程有一个全新的理解。我们下一章见。
