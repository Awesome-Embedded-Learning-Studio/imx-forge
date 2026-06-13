---
title: 板级配置基础
---

# 板级配置基础：Kconfig系统的那些坑和我们的第一次移植

## 为什么要写这一章

你可能会想，不就是改个配置文件吗，至于写一章？我刚接触 U-Boot 的时候也是这么想的。不就是 `make xxx_defconfig`，然后改几行代码编译吗？

然后现实给我上了一课。我第一次尝试移植板级配置的时候，直接复制了官方 EVK 板的 defconfig，改了改设备树名字，编译倒是过了。结果烧到板子上，我去，LCD花屏，网卡罢工，到处都是问题。

U-Boot 的配置系统不是简单的"要或不要"的问题，而是一张复杂的依赖网。选错一个配置，可能导致其他十个配置失效。而 Kconfig 系统本身就是从 Linux 内核搬过来的，设计初衷是给内核开发者用的，对于嵌入式工程师来说，上手曲线陡峭得令人发指。

所以这一章的目标很明确：我们要完整理解 U-Boot 的板级配置系统，从 defconfig 的本质、Kconfig 的工作原理、到 board/目录的组织方式、再到板级头文件的作用。最后，我们要基于 mx6ull_14x14_evk 创建自己的板级配置，理解每一个改动背后的原因。

## defconfig 到底是什么，Kconfig 系统是怎么工作的

先说个很多人不知道的事实：defconfig 不是完整的配置文件。

你可能会问，那 `configs/mx6ull_14x14_evk_emmc_defconfig` 里不是有一百多行配置吗，怎么不完整？事情是这样的，defconfig 只存储与默认值不同的配置选项。如果某个选项在 Kconfig 里默认是 n，而板子需要它设为 y，defconfig 里就会记录 `CONFIG_XXX=y`。但如果某个选项默认就是 y，板子也用 y，defconfig 里根本不会出现这一行。

这个设计很聪明，它让 defconfig 文件非常简洁。但对于新手来说，这是个坑。你以为 defconfig 里没写的配置就是没开，实际上可能默认就是开的。你以为改了 defconfig 就万事大吉，但 Kconfig 系统可能因为依赖关系把你的配置给关了。

当你运行 `make xxx_defconfig` 的时候，U-Boot 做了这些事情：首先读取指定的 defconfig 文件，然后扫描所有 Kconfig 文件构建配置树，接着评估每个配置符号的依赖关系和默认值，最后生成完整的 .config 文件。这个 .config 才是编译时真正使用的配置，它包含了 defconfig 的设置加上 Kconfig 系统计算出的所有默认值。

Kconfig 系统的语法是这样的：每个目录下都可以有一个 Kconfig 文件，定义这个目录相关的配置选项。配置选项之间可以有依赖关系，比如 `depends on MX6ULL` 表示这个选项只在选择了 MX6ULL 芯片时才可见。还有 `select` 关键字，表示选中某个选项时自动选中另一个。`imply` 关键字则表示"暗示"，即选中这个选项时，另一个选项默认也会被选中，但用户可以手动关闭。

最坑的是 `choice` 语句，它定义了一组互斥的选项，用户只能选其中一个。比如 mx6 的 Kconfig 里就有一个 choice 语句定义了各种 i.MX6 芯片型号，你选了 MX6ULL 就不能选 MX6UL。很多新手不知道这一点，看到一堆以 MX6 开头的配置，不知道该选哪个。

配置项的值有四种：y（编译进 U-Boot）、m（编译成模块，U-Boot 不支持）、n（不编译）、字符串或数字。绝大多数选项都是 y 或 n，字符串类型的常见于设备树路径、命令行参数等。

## 为什么不能直接用别人的 defconfig

这是很多新手会踩的坑：我的板子和官方 EVK 板硬件差不多，能不能直接用它的 defconfig？

理论上可以，但实际上有很多坑。首先是芯片型号的差异，i.MX6ULL 有 14x14 和 9x9 两种封装，某些外设在 9x9 封装上被熔丝裁掉了。如果你的板子用 14x14 封装却用了 9x9 的 defconfig，某些外设可能怎么都初始化不了。

其次是存储介质的差异，eMMC、NAND、QSPI Flash 的初始化完全不同。存储设备的配置在 defconfig 里看起来就几行，但背后涉及 DCD 配置、时钟设置、引脚复用一整套逻辑。用错了存储介质的 defconfig，轻则启动失败，重则板子变砖。

再者是时钟配置的差异，不同板子的外部晶振频率可能不同，DDR 参数可能不同。这些参数写死在 imximage.cfg 里，而 defconfig 不会体现这些差异。你用别人的 defconfig，生成的 imx 镜像可能时钟初始化就是错的。

最隐蔽的坑是依赖关系，某个板子的 defconfig 可能开了某个你不需要的选项，而这个选项又依赖了另外一堆配置。结果就是你的镜像体积膨胀，或者某些不需要的驱动被初始化了，占用启动时间。更糟糕的是，如果两个板子的配置有冲突，比如一个开了 DM_I2C 另一个开了旧的 I2C 框架，编译都可能不过。

所以正确的做法是找一个接近的参考板，复制它的 defconfig 作为起点，然后根据你的硬件实际情况调整。调整的时候不是简单的删减，而是要理解每个配置项的作用，检查它的依赖关系，确保修改后的配置是一致的。

## board/ 目录结构和板级初始化代码

说完了 defconfig，我们来看 board/ 目录。U-Boot 的 board/ 目录是按厂商和板型组织的，比如 `board/freescale/mx6ul_14x14_evk/` 就是 Freescale（现在是 NXP）的 mx6ull_14x14_evk 板。

一个典型的板级目录包含这些文件：Kconfig 定义了板子相关的配置选项，比如 `SYS_BOARD`、`SYS_VENDOR`、`SYS_CONFIG_NAME` 这些变量。Makefile 指定了要编译的源文件，通常是 `obj-y := mx6ul_14x14_evk.o`。MAINTAINERS 声明了这个板子的维护者和相关文件路径。imximage.cfg 是 NXP i.MX 系列专用的镜像头配置文件，定义了 DCD（Device Configuration Data）和各种初始化参数。而 `.c` 文件就是真正的板级初始化代码。

板级初始化代码通常包含这些函数：`dram_init()` 初始化 DDR 内存，告诉 U-Boot 有多少内存可用。`board_early_init_f()` 是早期初始化函数，此时 DDR 还没初始化，只能做一些极早期的设置。`board_init()` 是主要的初始化函数，设置启动参数、初始化外设。`board_late_init()` 是后期初始化函数，此时大部分驱动已经初始化完毕，可以设置环境变量、做最后的调整。`checkboard()` 用于在启动时打印板子信息。

你会发现这些函数名都是约定俗成的，U-Boot 的链接脚本会自动调用它们。你不需要在 main 函数里显式调用，只要按照命名规范实现函数就行。这种设计很巧妙，允许不同板子有不同的初始化流程，而不需要修改核心代码。

## include/configs/ 板级头文件解析

include/configs/ 目录是 U-Boot 配置的另一个重要部分。这里的 .h 文件在 Kconfig 系统引入之前是主要的配置方式，现在虽然很多配置迁移到了 Kconfig，但仍有大量配置保留在头文件里。

板级头文件通常包含这些内容：首先是基地址定义，比如 `UART1_BASE`、`USDHC2_BASE_ADDR`，这些是硬件寄存器的物理地址。然后是内存布局定义，比如 `PHYS_SDRAM`、`CFG_SYS_SDRAM_BASE`、`CFG_SYS_INIT_RAM_ADDR`，告诉 U-Boot 内存和内部 RAM 的位置。接着是外设配置，比如 MMC 的数量、NAND 的基地址、网络设备的默认设置。最后是环境变量定义，这是最重要的部分。

环境变量定义是一大坨宏定义的字符串，定义了 bootcmd、bootargs 等启动相关的变量。你可能会觉得奇怪，为什么环境变量要编译进代码，而不是存储在设备上？答案是冷启动时需要这些变量。第一次烧录时，设备上可能没有有效的环境变量存储，这时候编译进代码的默认值就派上用场了。

我们来看一个典型的环境变量定义：

```
#define CFG_EXTRA_ENV_SETTINGS \
    "script=boot.scr\0" \
    "image=zImage\0" \
    "console=ttymxc0\0" \
    "fdt_addr=0x83000000\0" \
    "bootargs=console=${console},${baudrate} root=${mmcroot}\0" \
    "bootcmd=run loadbootscript; run bootscript\0"
```

每个字符串以 `\0` 结尾，多个字符串用 ` \` 连接。U-Boot 启动时会把这些字符串合并成一个大的环境变量块，然后在运行时使用。

这里有个常见的坑：很多人改了头文件里的环境变量，结果编译后启动发现根本没生效。这是因为环境变量有两种来源：编译时默认值和存储设备上的值。如果存储设备上有有效的环境变量，U-Boot 会优先使用存储的值，忽略编译时的默认。所以要让修改生效，你需要用 `env default -f` 恢复默认值，或者用 `saveenv` 保存新的值。

另一个坑是字符串拼接。你可能会看到这样的定义：

```
"mmcargs=setenv bootargs console=${console},${baudrate} root=${mmcroot}\0"
```

这里的 `${console}` 和 `${baudrate}` 不是 shell 变量，而是 U-Boot 环境变量的引用。`mmcargs` 这个环境变量本身就是一个命令，执行它会设置 bootargs。理解这一点很重要，否则你会对启动日志里各种奇怪的变量名感到困惑。

## 实战：基于 mx6ull_14x14_evk 创建我们的板级配置

理论说得够多了，我们来看实战。假设我们的板子叫 "AES EMMC"，基于 i.MX6ULL 14x14 封装，使用 eMMC 存储。我们要基于 mx6ull_14x14_evk 创建自己的配置。

第一步是在 arch/arm/mach-imx/mx6/Kconfig 里添加新的目标。打开这个文件，找到 `TARGET_MX6ULL_14X14_EVK` 的定义，在它后面加上我们自己的：

```
config TARGET_MX6ULL_AES_EMMC
    bool "Support mx6ull_aes_emmc"
    depends on MX6ULL
    select BOARD_LATE_INIT
    select DM
    select DM_THERMAL
    select IOMUX_LPSR
    select IMX_MODULE_FUSE
    select OF_SYSTEM_SETUP
    imply CMD_DM
```

这里的 `depends on MX6ULL` 表示这个配置只在选择了 MX6ULL 芯片时才可见。`select` 语句表示选中这个目标时自动选中那些选项，比如 `DM`（驱动模型）、`BOARD_LATE_INIT`（启用后期初始化）。`imply` 语句表示暗示性选择，用户可以手动关闭。

这一步的作用是告诉 Kconfig 系统：有一个新的板型叫 mx6ull_aes_emmc，它依赖 MX6ULL，并且需要这些基础配置。没有这一步，你在 make menuconfig 里根本找不到这个选项。

第二步是创建板级目录和文件。复制 `board/freescale/mx6ul_14x14_evk/` 到 `board/freescale/mx6ull_aes_emmc/`，然后修改里面的文件。

先改 Kconfig，把所有 `mx6ul_14x14_evk` 替换成 `mx6ull_aes_emmc`：

```
if TARGET_MX6ULL_AES_EMMC

config SYS_BOARD
    default "mx6ull_aes_emmc"

config SYS_VENDOR
    default "freescale"

config SYS_CONFIG_NAME
    default "mx6ull_aes_emmc"

config IMX_CONFIG
    default "board/freescale/mx6ull_aes_emmc/imximage.cfg"

config TEXT_BASE
    default 0x87800000
endif
```

这里的 `SYS_BOARD` 指定了板级目录名，`SYS_CONFIG_NAME` 指定了头文件名，`IMX_CONFIG` 指定了 imximage.cfg 的路径，`TEXT_BASE` 指定了 U-Boot 在内存中的加载地址。i.MX6ULL 的 DDR 起始地址是 0x80000000，U-Boot 加载到 0x87800000，这个值是 NXP 规定的，不能随便改。

再改 Makefile：

```
obj-y  := mx6ull_aes_emmc.o
```

这告诉构建系统要编译 `mx6ull_aes_emmc.c` 并链接进去。

MAINTAINERS 文件声明了维护者和相关文件，可以改成你的名字：

```
AES IMX6ULL Board
M:	CharlieChen <725610365@qq.com>
S:	Maintained
F:	board/freescale/mx6ull_aes_emmc/
F:	include/configs/mx6ull_aes_emmc.h
F:	configs/mx6ull_aes_emmc_defconfig
```

第三步是创建板级头文件。复制 `include/configs/mx6ul_14x14_evk.h` 到 `include/configs/mx6ull_aes_emmc.h`，然后修改。

先看基本配置：

```
#define CFG_MXC_UART_BASE		UART1_BASE

#ifdef CONFIG_FSL_USDHC
#define CFG_SYS_FSL_ESDHC_ADDR	USDHC2_BASE_ADDR
#define CONFIG_SYS_FSL_USDHC_NUM	2
#endif
```

`CFG_MXC_UART_BASE` 指定了串口基地址，UART1_BASE 就是 UART1 的寄存器地址。`CFG_SYS_FSL_ESDHC_ADDR` 指定了 eMMC 控制器地址，USDHC2 是第二个 SD/eMMC 控制器。`CONFIG_SYS_FSL_USDHC_NUM` 是控制器数量，这里设为 2，表示有两个 USDHC 控制器。

再看环境变量定义，这是最关键的部分：

```
#define CFG_MFG_ENV_SETTINGS \
    CFG_MFG_ENV_SETTINGS_DEFAULT \
    "splashimage=0x83800000\0"\
    "eth0addr=b8:ae:1d:01:00:00\0"\
    "eth1addr=b8:ae:1d:01:00:04\0"\
    "initrd_addr=0x86800000\0" \
    "emmc_dev=1\0"\
    "sd_dev=1\0" \
    "\0"\

#define CFG_EXTRA_ENV_SETTINGS \
    CFG_MFG_ENV_SETTINGS \
    "script=boot.scr\0" \
    "image=zImage\0" \
    "console=ttymxc0\0" \
    "fdt_file=imx6ull-14x14-evk-emmc.dtb\0" \
    "fdt_addr=0x83000000\0" \
    "bootargs=console=${console},${baudrate} root=${mmcroot}\0" \
    "bootcmd=run loadbootscript; run bootscript\0"
```

`splashimage` 是开机 logo 的加载地址，`eth0addr` 和 `eth1addr` 是网卡的 MAC 地址。注意这里只是默认值，实际运行时可以从设备树或 OTP 里读取。`initrd_addr` 是 initramfs 的加载地址，`emmc_dev` 和 `sd_dev` 指定了存储设备编号。

`fdt_file` 指定了设备树文件名，这个必须和你的实际设备树文件名一致。`fdt_addr` 是设备树的加载地址，这个地址不能和内核地址冲突。`bootargs` 是传给内核的命令行参数，`console` 指定了控制台设备，`root` 指定了根文件系统。`bootcmd` 是自动启动时执行的命令。

第四步是修改板级 C 代码。打开 `mx6ull_aes_emmc.c`，核心函数是这些：

```
int dram_init(void) {
    gd->ram_size = imx_ddr_size();
    return 0;
}

int board_init(void) {
    gd->bd->bi_boot_params = PHYS_SDRAM + 0x100;
    setup_fec();
    return 0;
}

int board_late_init(void) {
    env_set("board_name", "EVK");
    env_set("board_rev", "14X14");
    setup_lcd();
    return 0;
}

int checkboard(void) {
    puts("Awesome Embedded Studio Authored\n");
    return 0;
}
```

`dram_init()` 告诉 U-Boot 有多少内存，`imx_ddr_size()` 会从设备树或硬编码的值读取内存大小。`board_init()` 设置启动参数，`gd->bd->bi_boot_params` 是内核参数在内存中的位置，通常放在 DDR 起始地址后面一点的地方。`setup_fec()` 初始化网络控制器。

`board_late_init()` 设置环境变量，`board_name` 和 `board_rev` 可以被启动脚本使用，用于选择正确的设备树或启动参数。`setup_lcd()` 初始化显示控制器，如果你的板子没有屏幕，可以注释掉。

`checkboard()` 只是打印一个字符串，用于确认板子类型。你可以改成自己的板子名字，启动时会看到。

第五步是修改 imximage.cfg。这个文件定义了 NXP Boot ROM 需要的镜像头格式，包括 DCD 数据。DCD 数据是一系列寄存器写入操作，Boot ROM 会在跳转到 U-Boot 之前执行这些操作，用于初始化 DDR、时钟等关键硬件。

如果你用的 DDR 和参考板一样，imximage.cfg 可以不用改。但如果你换了不同型号的 DDR，或者时钟配置不同，就需要修改这些寄存器值。具体怎么改，需要参考 DDR 芯片的手册和 NXP 的文档，这里就不展开了。

第六步是创建 defconfig。复制 `configs/mx6ull_14x14_evk_emmc_defconfig` 到 `configs/mx6ull_aes_emmc_defconfig`，然后修改关键配置：

```
CONFIG_ARM=y
CONFIG_ARCH_MX6=y
CONFIG_MX6ULL=y
CONFIG_TARGET_MX6ULL_AES_EMMC=y
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-aes"
CONFIG_BOOTCOMMAND="echo Current do not autoboot"
CONFIG_BOOTDELAY=-1
```

`CONFIG_TARGET_MX6ULL_AES_EMMC` 是我们新创建的目标，必须设为 y。`CONFIG_DEFAULT_DEVICE_TREE` 指定了默认设备树文件，这个必须和 arch/arm/dts/ 里的文件名一致。`CONFIG_BOOTCOMMAND` 是自动启动时执行的命令，这里先改成只打印一行，方便调试。`CONFIG_BOOTDELAY=-1` 表示不自动启动，等待用户输入，开发阶段这样比较安全。

其他配置项根据你的硬件实际情况调整。如果板子没有网络，可以把 `CONFIG_FEC_MXC`、`CONFIG_PHYLIB` 这些网络相关的配置删掉。如果不需要显示，可以把 `CONFIG_VIDEO` 相关的删掉。删掉不用的配置可以减小镜像体积，加快启动速度。

## 与正点原子配置的对比说明

正点原子的 Alpha/ELF 板子在圈子里很流行，很多教程都是基于它们的板子。但它们的做法和官方 NXP 有一些差异，这里对比一下。

首先，正点原子的 U-Boot 版本通常比较老，基于 2016 年左右的 NXP uboot-imx。那个版本的配置系统还没有完全迁移到 Kconfig，大量配置仍然在头文件里。所以他们的教程里让你改 `mx6ullevk.h`，而在新版本里很多配置应该用 menuconfig 改。

其次，正点原子的板级目录结构和官方不太一样。他们可能有自己的板级目录，比如 `board/freescale/mx6ull_alientek/`，或者直接复用 `mx6ul_14x14_evk`。如果你用的是他们的教程，要注意检查板级目录和 defconfig 的对应关系。

再者，正点原子的设备树组织方式也可能不同。官方的设备树文件在 `arch/arm/dts/` 目录下，而正点原子可能有自己的目录或命名规则。移植的时候要注意设备树文件的路径和命名，确保 defconfig 里的 `CONFIG_DEFAULT_DEVICE_TREE` 指向正确的文件。

最后，正点原子的环境变量设置可能更简化，因为他们假设你只从一种介质启动。官方的配置则考虑了多种启动方式，环境变量的逻辑更复杂。如果你只从 eMMC 启动，可以简化 bootcmd，但保留其他启动方式有利于调试和灵活切换。

## 写在最后

板级配置是 U-Boot 移植的第一步，也是最重要的一步。配置选对了，后面的驱动移植会顺水推舟。配置选错了，你会遇到各种莫名其妙的错误，排查半天发现源头在配置。

理解 Kconfig 系统的工作原理很重要，它不是简单的"要或不要"，而是一个复杂的依赖网。修改配置时要考虑上下游依赖，确保修改是一致的。不理解原理的复制粘贴，迟早会踩坑。

board/ 目录和 include/configs/ 目录是板级代码的核心，一个控制初始化流程，一个定义硬件参数和环境变量。理解这两个目录的作用和关系，你就掌握了 U-Boot 板级移植的一半。

下一章我们会深入设备树移植，那是更复杂的坑。但有了板级配置的基础，设备树移植就只是体力活了。记住，U-Boot 不是黑魔法，每一步都有它的原因。理解原因比记住命令更重要。
