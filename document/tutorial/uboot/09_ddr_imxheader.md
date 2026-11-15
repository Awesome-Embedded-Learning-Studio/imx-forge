---
title: DDR 初始化与镜像头：imximage.cfg 里写了什么
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# DDR 初始化与镜像头：imximage.cfg 里写了什么

> 本篇解决一个工程问题：U-Boot 还没跑起来之前，DDR 是被谁带活的，这件事归哪个文件管、改哪里、错了会怎样。概念篇（01 章）从 BootROM 的视角提过一次 DCD，七步造板卡那章（07 章）把 imximage.cfg 挂进了 Kconfig，还留了一句具体怎么改不展开，产物验证与烧录（04 章）里咱们已经跟镜像头的前 64 字节照过一回面。本篇把这三条线接起来，停在能对上号的深度，逐字段的字节级语义归扩展卷 boot-chain 讲启动链的那一篇，眼下以 NXP 参考手册为准。

## 一、为什么 DDR 要有人初始化

咱们按一次复位键，头一条指令不在卡上，也不在 DDR 里，在芯片出厂就固化好的 BootROM 里。BootROM 挑启动介质、把镜像开头读进片内 RAM，这些概念篇讲过了，本篇要接手的是它接下来的一件事：把 DDR 带活。U-Boot 的入口定在 0x87800000，DDR 起始在 0x80000000（七步造板卡那章说过这两个数），跳转目标落点的整片空间，此刻是死的。上电那一瞬，DDR 控制器的寄存器全是默认值，时钟没开，刷新没跑，颗粒要的时序参数一个都没配，外面那颗内存连一个字节都存不进去。指令跳过去就是空转。

DDR 怎么活？靠 BootROM 执行一份寄存器写入清单，清单的名字叫 DCD（Device Configuration Data，设备配置数据）。机制要放在芯片设计里看：BootROM 是固化代码，改不了，它不认识咱们板上装的是哪家哪款颗粒，也不必认识，因为一块芯片要服务千万块板子，颗粒型号百花齐放。咱们把颗粒换成另一款型号，变化全部落在寄存器值上——时钟配多少、时序排多紧、驱动强度开多强，一块板一套数。NXP 的办法是把这套数做成清单，镜像头里放一个指针指向它，BootROM 照单逐条写寄存器，写完 DDR 才算活，然后才敢把镜像本体搬进 DDR、跳进入口。顺序在概念篇的链条里排得明白：BootROM 执行 DCD，DDR 可用，再跳 U-Boot。跳之前那一下谁都替不了，U-Boot 自己想配 DDR，得先有内存把代码装进去，鸡生蛋的圈就卡在这里，所以清单必须由 BootROM 动手执行。

## 二、DCD 是一段寄存器写入清单

嘴上说清单不算数，咱们拿参考产物自己看。xxd 真跑给咱们看，AES 板的产物在 /tmp/uboot-ref-aes：

```bash
# 主机 ~/imx-forge
xxd -l 64 /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 0000 1a00 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
```

头四个字节 d1 00 20 40，04 章认过一回：0xD1 是 IVT 的身份标记，中间 00 20 拼出长度 0x0020，IVT 自身 32 字节，末尾 0x40 是 IVT 结构自己的版本字段。本篇咱们把目光挪到指针区。偏移 0x04 的四个字节小端读出 0x87800000，是入口，往后 mkimage 的判读还会报同一个数。偏移 0x0C 的字读出 0x877FF42C，这一项就是 DCD 指针，清单在哪，头里写得明白。小端是低位字节排前头，IVT 头里的指针都按这个法子倒着读，入口、DCD 指针、自指针三处都是。DCD 段里的数另有一套排法：mkimage 写这段用的是 tools/imximage.c 里的 cpu_to_be32（第 252、255 行），地址和值按大端存，顺着字节直接念才是地址和值本身。

指针指的数跟文件偏移能对上号。偏移 0x14 的字是 0x877FF400，IVT 自己在内存里的落点。这个落点不是此刻就成立的：BootROM 先把头读进片内 RAM 解析，等 DCD 把 DDR 带活，再照 boot data（IVT 里报镜像搬进内存的起点与长度的那一小段）把镜像搬进 DDR，头这才落到 0x877FF400，指针在那里才有效。（转储偏移 0x20 的字读出 0x877FF000，就是搬进的起点）。咱们拿 0x877FF42C 减 0x877FF400，得 0x2C，回头看转储，文件偏移 0x2C 处站的正是 d2 01 e8 40 四个字节。这就是 DCD 自己的头：0xD2 是清单的身份标记，跟 IVT 的 0xD1 成对。中间两个字节拼出长度 0x01E8，折合 488 字节。末尾的 0x40 还是版本字段。紧接着 cc 01 e4 04，0xCC 是写入命令的标记，0x01E4 折合 484 字节是这条命令连同数据的长度，末尾那个 0x04 是参数字节。从这里起，剩下的字节就是一条条“往哪个地址写什么值”。

数字也来对一遍，咱们把数算清。行数能算出长度，imximage.cfg 里 DATA 行一共 61 行，其中 1 行包在 CONFIG_IMX_OPTEE 条件里，参考构建没开 OPTEE（.config 里 OPTEE 相关几项都是 not set），真正编进 DCD 的是 60 条。一条 DATA 行按 4 字节地址加 4 字节值共 8 字节，60 条 480 字节，加命令头 4 字节得 484，等于 0x01E4，再加清单头 4 字节得 488，等于 0x01E8，跟转储里两个长度字段互相作证。尺寸这边同样有数，转储偏移 0x24 的字读出 0x001A0000，折合 1703936，跟 mkimage 留下的 log 里 Data Size 相等，imx 文件本身 1702912 字节，比它少 1024，少的一格是介质上让给分区表的位置，04 章在 EVK 上算过同一笔数，AES 这边同样咬合。

清单头一条写的是哪里，转储里看得见。跟在命令头 cc 01 e4 04 后面的四个字节 02 0c 40 68，站在偏移 0x34，顺着念就是清单头一条的地址 0x020C4068，再往后四个 ff 是值 0xffffffff。咱们翻开 imximage.cfg 第 53 行，写的是 DATA 4 0x020c4068 0xffffffff，一字不差。这个地址在 CCM（时钟控制模块）的寄存器区，基址 0x020C4000 加 0x68，那行注释写着 Enable all clocks。cfg 开头 7 条落在 0x020C4068 到 0x020C4080，是七个时钟门控寄存器，全开，DDR 控制器要的时钟从这里来。

深度的边界在这里交代。本篇认到头标记、长度、指针、清单位置，外加第一条写入跟源文件的对应，排查烧录问题够用了。每个字节再往里追——参数字节 0x04 怎么编码、写入命令还分哪几种、校准值哪一位是什么——那是字节级语义，以 NXP i.MX6ULL 参考手册讲 BootROM 与镜像格式的部分为准，扩展卷 boot-chain 有专场，笔者这里不装懂。

## 三、AES 的 imximage.cfg

### 文件开头：镜像版本、启动介质与插件行

真相源就是板级目录里这份 2879 字节的文本文件，咱们把开头 60 行读出来：

```bash
# 主机 ~/imx-forge
sed -n '1,60p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Copyright (C) 2016 Freescale Semiconductor, Inc.
 * Copyright 2017 NXP
 *
 * Refer doc/imx/mkimage/imximage.rst for more details about how-to configure
 * and create imximage boot image
 *
 * The syntax is taken as close as possible with the kwbimage
 */

#include <config.h>

/* image version */

IMAGE_VERSION 2

/*
 * Boot Device : one of
 * spi/sd/nand/onenand, qspi/nor
 */

#ifdef CONFIG_QSPI_BOOT
BOOT_FROM	qspi
#elif defined(CONFIG_NOR_BOOT)
BOOT_FROM	nor
#else
BOOT_FROM	sd
#endif

#ifdef CONFIG_USE_IMXIMG_PLUGIN
/*PLUGIN    plugin-binary-file    IRAM_FREE_START_ADDR*/
PLUGIN	board/nxp/mx6ull_aes_emmc/plugin.bin 0x00907000
#else

#ifdef CONFIG_IMX_HAB
CSF CONFIG_CSF_SIZE
#endif

/*
 * Device Configuration Data (DCD)
 *
 * Each entry must have the format:
 * Addr-type           Address        Value
 *
 * where:
 *	Addr-type register length (1,2 or 4 bytes)
 *	Address	  absolute address of the register
 *	value	  value to be stored in the register
 */

/* Enable all clocks */
DATA 4 0x020c4068 0xffffffff
DATA 4 0x020c406c 0xffffffff
DATA 4 0x020c4070 0xffffffff
DATA 4 0x020c4074 0xffffffff
DATA 4 0x020c4078 0xffffffff
DATA 4 0x020c407c 0xffffffff
DATA 4 0x020c4080 0xffffffff

```

34 行起是 #else 与 HAB 的条件编译，40 到 50 行是一段 DCD 格式注释，53 行起进入 DATA 表，第二节引过的头一条就在那里。

IMAGE_VERSION 2 声明镜像格式版本，mkimage 判读里那行 Image Ver: 2 就是它，镜像格式文档 doc/imx/mkimage/imximage.txt 写明这个值只认 1 和 2：1 是 mx25/mx35/mx51 那代老芯片用的，2 是 mx53/mx6 用的，出了这两个值直接报错、镜像生成不出来。咱们这块 i.MX6ULL 落在 2 那一档，所以写 2。咱们别把它跟 IVT 头里那个 0x40 混为一谈，前者选的是格式路线，后者是 IVT 结构自己的版本字段，两码事。

BOOT_FROM 是三个分支。开了 QSPI 启动写 qspi，开了 NOR 启动写 nor，都没开落 sd。咱们翻参考构建的 .config（/tmp/uboot-ref-aes 下那份），第 424 行写着 CONFIG_QSPI_BOOT is not set，NOR 启动同样没开，三个分支落进 else，写的是 sd。这个命令决定 BootROM 到介质哪个字节找头：格式文档给了六种取值，nand、spi、sd、onenand、nor、sata，构建工具 tools/imximage.c 的对照表把 sd 对到 SD Card，再查 arch/arm/include/asm/mach-imx/imximage.cfg 第 17 行，sd 这一类取 FLASH_OFFSET_STANDARD，值 0x400。0x400 折合 1024，BootROM 到介质第 1024 字节找 IVT，flash 卷启动链路篇核过的就是它。

PLUGIN 那一小段咱们按住不表，本节末尾细讲。

### 寄存器写入表：三段各管一段

#else 之后才是这张表的本体。60 条 DATA 行分三段，笔者一段段数过：头 7 条地址落在 0x020C4068 到 0x020C4080，全在 CCM 里，把时钟门全开。中间 19 条地址都落在 IOMUXC（引脚配置模块，基址 0x020E0000）上，散布在 0x020E0244 到 0x020E04B4 之间，是 DDR 引脚这一片的 pad 配置，驱动强度、上拉这一类参数一条条定下来。尾段 34 条地址围着 0x021B0xxx 转，基址 0x021B0000 是 MMDC（i.MX6ULL 的 DDR 控制器）的寄存器区，时钟配置、时序参数、模式寄存器设置、读写校准全在这一段。7 加 19 加 34 等于 60，跟第二节那笔 480 字节的算术对上了。

行格式从格式文档里来：DATA 后面跟类型、地址、值三个字段，类型 4 表示按 4 字节写（2 是半字、1 是字节），地址是寄存器物理地址，值全用十六进制。文档还写了上限：镜像版本 1 最多 60 条写入命令，版本 2 放宽到 220 条。咱们点一遍，正好 60 条，离 220 远，跟版本 1 的老上限同数，算个巧合，留个印象就好。

板级目录里还住着一份 imximage_lpddr2.cfg，125 行、2935 字节。两份文件结构一模一样，BOOT_FROM 的分支、OPTEE 条件全都同款，差别全在寄存器值上，笔者把关键几处摆在一起看：

| 对比项 | imximage.cfg（DDR3） | imximage_lpddr2.cfg（LPDDR2） |
|---|---|---|
| 体量 | 120 行，2879 字节 | 125 行，2935 字节 |
| DATA 行 | 61 行，60 条编进 DCD | 64 行，63 条编进 DCD |
| 三段分布 | 7 条时钟加 19 条 IOMUXC 加 34 条 MMDC | 7 条时钟加 19 条 IOMUXC 加 37 条 MMDC |
| IOMUXC 首条 | 0x020E04B4 写 0x000C0000 | 0x020E04B4 写 0x00080000 |
| MMDC 段差别 | 没有 0x021B085C | 有 0x021B085C 等寄存器 |

笔者把两份文件里同一个地址 0x020E04B4 对着看，DDR3 那份写 0x000C0000，LPDDR2 那份写 0x00080000，这个字段选的是引脚组的颗粒类型与电压档，字段名与位的含义以参考手册为准。MMDC 段差得更远，LPDDR2 那份多出 0x021B085C 这类 DDR3 那份没有的寄存器，时序与校准值整套不同。颗粒类型换了，控制器要按新颗粒的协议重新走一遍初始化序列，改一两个数是糊弄不了控制器的。

用哪份由构建配置定。咱们在参考构建的 .config 第 193 行看到 CONFIG_IMX_CONFIG=“board/nxp/mx6ull_aes_emmc/imximage.cfg”，七步造板卡那章带咱们见过它的 default：IMX_CONFIG 指到哪份，mkimage 就拿哪份生成头。换 LPDDR2 颗粒的板子，把这个指向改到 lpddr2 那份即可，文件层面的分工就这么一层。

### plugin.S：plugin 路线的现场

板级目录 7 个文件里还有一个 plugin.S，5181 字节、263 行，笔者拿 wc -l 数过，263 行真实存在。它给另一条启动路线备料，咱们先把板级目录整列出来：

```bash
# 主机 ~/imx-forge
ls -la third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/
```

```text
total 40
drwxr-xr-x  2 charliechen charliechen 4096 Oct 17 15:04 .
drwxr-xr-x 76 charliechen charliechen 4096 Oct 17 15:04 ..
-rw-r--r--  1 charliechen charliechen  269 Oct 17 15:04 Kconfig
-rw-r--r--  1 charliechen charliechen  170 Oct 17 15:04 MAINTAINERS
-rw-r--r--  1 charliechen charliechen  116 Oct 17 15:04 Makefile
-rw-r--r--  1 charliechen charliechen 2879 Oct 17 15:04 imximage.cfg
-rw-r--r--  1 charliechen charliechen 2935 Oct 17 15:04 imximage_lpddr2.cfg
-rw-r--r--  1 charliechen charliechen 3746 Oct 20 09:38 mx6ull_aes_emmc.c
-rw-r--r--  1 charliechen charliechen 5181 Oct 17 15:04 plugin.S
```

plugin 路线是怎么回事：把 cfg 顶部的条件 CONFIG_USE_IMXIMG_PLUGIN 打开，PLUGIN 行生效，mkimage 编进镜像的就是一小段固件，清单那部分不挂了。BootROM 把这段固件装进片内 RAM 的 0x00907000 执行——这个地址就在片内 RAM 里，IRAM 基址 0x00900000 概念篇查过——固件头一件事是配 DDR，配完再调 BootROM 提供的复制函数，把镜像本体从介质搬进 DDR。plugin.S 的两个宏把这套活写成汇编：imx6ull_ddr3_evk_setting 与 imx6ull_lpddr2_evk_setting 各配一种颗粒，文件末尾一个条件编译按板子选宏，9x9 EVK 走 LPDDR2，其余走 DDR3，末行引 arch/arm/include/asm/arch-mx6/mx6_plugin.S 的公共插件代码收尾。宏里的写入跟 imximage.cfg 的 DATA 行是同一套数，笔者核过两处：IOMUXC 基址加 0x4B4 写 0x000C0000，MMDC 基址加 0x800 写 0xA1390003，加出来正好是 cfg 第 66 行与第 86 行那两个地址，值也一字不差。两条路线写同一批寄存器，差别只在谁执行、什么时点执行。

咱们这块参考板没走 plugin 路线。配置这边，咱们在 .config 第 243 行看到 CONFIG_USE_IMXIMG_PLUGIN is not set，cfg 里那段条件编译不生效，PLUGIN 行处在备而不用的状态。产物这边，mkimage 构建时自己留下的判读文件 /tmp/uboot-ref-aes/u-boot-dtb.imx.log 也答得出，咱们贴出来看：

```text
Image Type:   Freescale IMX Boot Image
Image Ver:    2 (i.MX53/6/7 compatible)
Mode:         DCD
Data Size:    1703936 Bytes = 1664.00 KiB = 1.62 MiB
Load Address: 877ff420
Entry Point:  87800000
```

Mode: DCD 三个字母替咱们作证，镜像里挂的是清单。补丁侧咱们也能对上号，patches/uboot-mainline/charlies_board.patch 里 PLUGIN 行两处都在：

```bash
# 主机 ~/imx-forge
grep -n "plugin" patches/uboot-mainline/charlies_board.patch | head -6
```

```text
921:+/*PLUGIN    plugin-binary-file    IRAM_FREE_START_ADDR*/
922:+PLUGIN	board/nxp/mx6ull_aes_emmc/plugin.bin 0x00907000
1048:+/*PLUGIN    plugin-binary-file    IRAM_FREE_START_ADDR*/
1049:+PLUGIN	board/freescale/mx6ullevk/plugin.bin 0x00907000
1312:diff --git a/board/nxp/mx6ull_aes_emmc/plugin.S b/board/nxp/mx6ull_aes_emmc/plugin.S
1316:+++ b/board/nxp/mx6ull_aes_emmc/plugin.S
```

咱们逐行看：922 行是 AES 板那份 cfg 里的 PLUGIN 行，1049 行是 lpddr2 那份里的，它指向的还是 board/freescale/mx6ullevk/plugin.bin，这份 lpddr2 cfg 是从 EVK 原版复制过来改的，插件路径没跟着改，真要启用 plugin 路线，这里得换成自己板级目录的 plugin.bin。1312 行起是 plugin.S 整文件的 diff 头。路线真实存在、想切随时能切，当前构建选了 DCD 这条，仅此而已。

## 四、改 DDR 参数意味着什么

换颗粒、换容量，动的就是这张 DATA 值表。值从哪来，来路无非三条：DDR 厂商的参考设计或数据手册、硬件同事给的寄存器清单、NXP 官方的 DDR 工具按新颗粒生成的脚本。任一处来源，照着新颗粒的初始化序列整段换。按段动手：IOMUXC 段 19 条管引脚电气，颗粒换了电压档与驱动要求，pad 值跟着换。MMDC 段 34 条管控制器，时钟配置、时序、模式寄存器、校准按新颗粒的协议排。有个细节值得咱们看：0x021B001C 这个地址在表里出现了八回，它是 MMDC 的命令寄存器（参考手册里叫 MMDC_MDSCR），前两回写 0x00008000 让控制器停着待命，中间五回每次带不同的低位数，把 DDR3 的模式寄存器挨个设置一遍，最后一回写 0 收尾。模式寄存器这一套是 DDR3 初始化协议的固定步骤，手册里有完整的时序要求，这就是为什么换颗粒不能只改几个看着像频率的数，整段得跟着序列走。

设备树那一侧的边界也要划清。咱们在设备树那章（08 章）见过，DDR 在设备树里只剩一条 memory 节点，reg 写 0x80000000 与 0x20000000，它声明的是这块内存从哪到哪，给 U-Boot 与内核分配内存用。颗粒怎么被带活、时序怎么排，设备树一个字都不管，归这份 cfg 管。两个文件别改串了位置：容量变了，memory 节点的 size 与 cfg 里的控制器配置要一起核，只动一边就埋下不一致，U-Boot 起来之后才会发作，查起来比启动失败还绕。改完的验证咱们能做的有两步，重新构建后拿第五节那条 xxd 看 0x30 起的字节变没变，对上了再放到板子上验。

::: warning 写错 DDR 参数，串口一行都不出
后果：DATA 表的值跟颗粒对不上，BootROM 照单写完照样往下走，DDR 实际没被带活，镜像本体搬不进 0x87800000，U-Boot 的第一条指令都执行不了，串口一个字符都不会有，全程没有一句报错。根因在 BootROM 的分工：它只管把清单执行完，不检查写入的值对不对、DDR 有没有真的活过来，验证这一步交给了镜像本体，而镜像本体此刻进不了内存。所以排查上电无输出，DDR 初始化是最先要怀疑的位置之一，烧录偏移错、镜像截断、拨码错同样都是静默。咱们手里能做的，是把 cfg 的值跟颗粒的参考脚本逐条核对，这是这类问题里最要紧的一步。
:::

## 五、本篇与 boot-chain 的分工

工程上的三件事，咱们在本篇管完：改哪里（DATA 值表与 IMX_CONFIG 的指向）、为什么（BootROM 照清单把 DDR 带活）、错了会怎样（静默无输出，DDR 初始化是最先要怀疑的位置之一）。镜像头里每个字节怎么读，IVT 各字段的完整语义、boot data 的结构、DCD 命令的全部编码，归扩展卷 boot-chain，那一篇还没写出来，眼下以 NXP i.MX6ULL 参考手册讲 BootROM 与镜像格式的部分为准。

留一条咱们自己就能跑的自证命令。自己构建的产物在 out/uboot，拿同样的 xxd 看头 64 字节：

```bash
# 主机 ~/imx-forge
xxd -l 64 out/uboot/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 0000 1a00 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
```

这份产物是 10 月 20 日编的，跟参考产物 11 月 14 日那轮隔着三周半，头 64 字节一个字节不差，尺寸同为 1702912 字节。原因不神秘：头区内容由 defconfig 与 imximage.cfg 决定，入口 0x87800000、DCD 指针 0x877FF42C、那 60 条寄存器写入，两轮构建吃的是同一套配置，头就不会变。咱们哪天换了颗粒、改了 cfg，再跑这条命令，0x30 起的那些字节就会跟本篇贴的不一样，改没改对，跟颗粒的参考脚本对一遍，当场有数。

## 继续学习

- [七步造出咱们的板卡](./07_board_porting.md)：IMX_CONFIG 的 default 写在 Kconfig 里，改 cfg 指向从那边进。
- [设备树](./08_device_tree_aes.md)：上一章，memory 节点与 cfg 的分工本篇刚划过界。
- [启动链路与偏移](../flash/04_imx6ull_boot_flow_and_offsets.md)：BootROM 到介质哪个字节找头，1024 的完整来历在那边。
