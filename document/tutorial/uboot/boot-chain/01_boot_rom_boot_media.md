---
title: 上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 上电之后：Boot ROM 怎么挑启动介质、认出咱们的镜像

> 本篇接住一个悬在咱们心里的问题：镜像写到 1 KiB 偏移，板子到手一上电，凭什么就活。答案在芯片里那段咱们从来没机会单步的代码上——它叫 Boot ROM，挑介质，按固定偏移找头，认格式，替咱们把 DDR 拉起来，然后才轮到 U-Boot。上一篇咱们把四个产物验了一遍，SD 与 eMMC 两条烧录路也交代完了，本篇往回退一步，把上电到 U-Boot 接手之间那段看不见的活儿讲清楚，下一篇再把镜像头一个字段一个字段过。芯片内部发生的动作本环境验不到，哪里没验、以什么为准，文中用标注容器圈出。

## 一、Boot ROM 是谁：芯片出厂就带着的第一段代码

咱们按下复位键以后，最先拿到执行权的是芯片里一段谁也没往板子上烧过的代码，U-Boot 得排在它后面。它叫 Boot ROM，固化在芯片内部的只读存储器里，出厂就带着，掩膜工艺一次成型，咱们烧不进、改不掉，板子的文件系统里也翻不出对应它的文件。对咱们来说它是个既成事实，每次上电它都在，每次都干同样的活儿，把控制权送到下一棒手里。NXP 出厂时把这段代码连同它认的格式一起定了下来，咱们后面要读到的 IVT 与 DCD 两种标记，就是它认格式的两把尺子。

为什么要把它做进只读存储器，咱们替它想一遍处境就明白了。上电那一刻，DDR 还没初始化，时钟还没配，分区表没人解析，文件系统没人认，芯片手里什么家当都没有，却得有个地方取出第一条指令。掩膜 ROM 是随芯片一起造出来的，掉不了，也写不坏，更不依赖任何外设，正好当这个起点。这也顺手解释了它为什么兼任救援通道，万一 flash 里的启动镜像被写坏，芯片也没变砖，把 BOOT_MODE 拨到串行下载模式，Boot ROM 就守着 USB 等主机喂一份新的进来，UUU 烧录靠的正是这条备用入口。

它的活儿有一条清楚的次序，咱们按次序摆开。上电后按配置挑一块启动介质，接着到介质开头的固定偏移把镜像头读进片内 RAM，验标记，再照头里的指引执行一段初始化清单，把 U-Boot 搬进内存，然后跳进去。跳进去那一刻 Boot ROM 的使命就到头了，除非再来一次复位，它不会再被执行。

跟 U-Boot 的分工，咱们两句讲完。Boot ROM 不认识文件系统，它不解析分区表，不认 ext4，只按扇区读裸数据，只认固定偏移和固定格式，所以它找 U-Boot 找的是介质开头那一段裸区，跟 boot 分区毫无关系。Boot ROM 跳进去那一刻，U-Boot 就接手，读分区、挂文件系统、拉内核全是它的事。上一篇交代 dd 烧卡的写法时，镜像要写到 1 KiB 的整盘裸区而不是写进 boot 分区，根子就在这里，那个位置是 Boot ROM 的搜索点，boot 分区得等 U-Boot 起来才有人认得。还有一层边界交代给咱们，有的方案在 Boot ROM 与完整 U-Boot 之间垫一层 SPL 二级加载器，本仓库这条链没有垫，构建日志里没有编 SPL 本体的行，SPL 只在 spl_size_limit 和 sfspl 这两个宿主工具名里露过脸，sfspl 是给 StarFive 板子做 SPI 启动镜像的工具，跟这颗芯片无关。产物清单里没有任何 SPL 文件，Boot ROM 执行完清单直接跳的就是完整 U-Boot。

## 二、它怎么挑启动介质

介质从哪来，咱们把它当机制看。复位的那一瞬间，Boot ROM 采样 BOOT_MODE 引脚上的电平，这个输入只分挡，串行下载或正常启动，介质扫描的次序它不管，次序另有来源。上一篇把启动拨码写进了上电前的核对清单，管的就是这一步的模式选择，拨码拨的是引脚电平。落在串行下载模式，芯片守着 USB 等主机喂镜像，这条路的全程在 [UUU + UMS eMMC 烧录](../../flash/10_uuu_ums_emmc_flashing.md)。它也是救援通道——板上一个系统都没有、flash 里空空如也，只要模式拨对，主机照样能把一份 U-Boot 送进内存，让板子活过来。落在正常启动，次序谁当家要看 BT_FUSE_SEL 这一位熔丝。烧成了 1，OCOTP 那排一次性可编程的位里记着的主启动介质和后备介质就当值，Boot ROM 依着次序扫。开发板出厂常态是这一位没烧，次序由 LCD_DATA00~17 这排配置引脚复位时的电平当场定，拨码拨的往往就是这排引脚，SD 与 eMMC 走 uSDHC 控制器这一路，SPI NAND 与 NAND 各有各的找法，NAND 上面还多一层 FCB 结构，那是 NAND 闪存开头的一张配置块，Boot ROM 靠它知道镜像在 NAND 里的摆放参数。主介质上扫不到合格镜像就退后备，两处都空手才罢休，扫到哪块介质交出合格镜像，就在哪块停。

拨码与熔丝的分工咱们摆正。拨码给的是复位那一刻的当场电平，熔丝记的是产线写进芯片的长期配置。串行下载模式由 BOOT_MODE 引脚强令，这一档拨码说了算。正常启动档里，介质次序默认由 LCD_DATA00~17 这排配置引脚当场定，拨码拨的常常就是它们，BT_FUSE_SEL 烧成 1，次序才交给熔丝当值。所以这排拨码救援路和日常路都管，差别只在档位，熔丝要在产线烧过 BT_FUSE_SEL 时才说话。主介质与后备介质的两级安排也有讲究，一块板常常焊着不止一种存储，eMMC 当主角、SD 卡当后备是常见搭配，主角上的镜像坏了，Boot ROM 还有第二个落脚点可试。

本篇后面贴的命令与转储全部来自主机上的产物文件，芯片里没验到的部分，咱们拿文件里的字段跟手册口径互相印证，印得上的讲，印不上的明说没把握。

## 三、它怎么认出咱们的镜像

位置有了还不够，Boot ROM 还得认得出读回来的数据是一张合格镜像。咱们拿 xxd 把参考产物的头 64 字节倒出来，先看 EVK 这份。

```bash
# 主机 ~/imx-forge
xxd -l 64 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

```text
00000000: d100 2040 0000 8087 0000 0000 2cf4 7f87  .. @........,...
00000010: 20f4 7f87 00f4 7f87 0000 0000 0000 0000   ...............
00000020: 00f0 7f87 00b0 0600 0000 0000 d201 e840  ...............@
00000030: cc01 e404 020c 4068 ffff ffff 020c 406c  ......@h......@l
```

### 门牌与地址：把 64 字节读成一张索引卡

咱们先认门牌。头四个字节 d1 00 20 40，d1 是标记，Boot ROM 见到它才认出这是 IVT，Image Vector Table，镜像向量表，一张 32 字节的索引卡。跟着的 0020 是头自身的长度，0x0020 恰好 32 字节。40 是头的版本字节，咱们手头两份产物里都是它，同一代 i.MX6 用的都是这套头格式。版本号咱们顺带分清两个：上一篇 mkimage -l 报的 Image Ver 2 来自 cfg 文件里 IMAGE_VERSION 2 那一行，标的是镜像格式的版本，跟头协议里这个 0x40 是两码事。

接着往下全是地址，咱们把转储里的字节按小端拼起来逐项对上。小端读法现场练一遍，转储里写的是 00 00 80 87，左边是低地址，拼 32 位数时右边的 87 顶到最高位，拼出来就是 0x87800000。再练一个，2c f4 7f 87 拼出 0x877ff42c，跟表里 DCD 的位置一行对上，这个数到第四节还要当主角。

| 头里偏移 | 转储里的字节 | 按小端读是 | Boot ROM 拿它做什么 |
| --- | --- | --- | --- |
| 0x04 | 00 00 80 87 | 0x87800000 | 执行完初始化清单后跳进 U-Boot 的入口 |
| 0x08 | 00 00 00 00 | 保留位 | Boot ROM 不读它，mkimage 补零凑格式 |
| 0x0c | 2c f4 7f 87 | 0x877ff42c | 初始化清单 DCD 的位置 |
| 0x10 | 20 f4 7f 87 | 0x877ff420 | boot data 的位置 |
| 0x14 | 00 f4 7f 87 | 0x877ff400 | IVT 自己被搬进内存后住的地方 |
| 0x18 | 00 00 00 00 | 0，没有 CSF | 签名块的位置，零表示这份镜像没走签名 |

入口那一项值得咱们核一眼。0x87800000 正是上一篇 readelf 报的 Entry point address，源头是 out/uboot/.config 第 183 行的 CONFIG_TEXT_BASE=0x87800000，/tmp/uboot-ref-evk/.config 同一行同值，链接脚本按它排布代码。同一处入口咱们对上了三处，ELF 头报过它，镜像头里躺着它，CONFIG_TEXT_BASE 定下了它，链条这才算通。这些地址也不是拍脑袋填的，咱们把来源追一下，入口从配置来，self 与 DCD 的位置跟着入口和清单长度倒推，mkimage 打包时一并算好填进卡里，改一处配置，三个地址一起跟着变。IVT 的 self 指向 0x877ff400，比入口低 0xC00，这 3 KiB 装的是头、boot data 和 DCD，U-Boot 本体从那之后才开始。0x18 那个零也有话说，CSF 是签名块的指针，零表示没有签名块，签名那一套叫 HAB，高安全要求的产线才用，本仓库两份产物都走无签名这条路。

0x20 起还有一张小表，咱们把它也读掉。boot data 三个字各管一件事，00 f0 7f 87 拼出 0x877ff400，镜像在内存里的起始地址，正好跟 self 同址。上一篇正文把这个字写成了 0x877FF000，按小端对回它自己贴的转储是 0x877ff400，本篇照转储读，顺手替上一篇记一笔勘误。00 b0 06 00 拼出 0x0006b000，这份镜像的大小，末尾那个零是插件标记，零表示不用插件。位置、大小、去处，Boot ROM 要的全部信息就在这一张卡上。

再说 1 KiB，咱们把位置对一遍。Boot ROM 到介质开头的固定偏移 0x400 去读这张 IVT，不多不少。烧卡时 dd bs=1K seek=1 把整份 .imx 从 1 KiB 偏移写进去，文件开头的 IVT 恰好落在 0x400，两边会师。这个偏移顺带给分区表让了位，MBR 占着开头的扇区，头的搜索点挪到 0x400，中间还空出一个整扇区。搜索点是芯片定下的死数，镜像要是挪去 0 偏移，Boot ROM 不会跟着往前找，0x400 只会落空。写偏了的后果很直接。Boot ROM 在 0x400 读回来的就不是 d1 开头的字节，介质被判成没有镜像，它退出去扫下一块候选，串口自然一个字都不出。这也把上一篇的一个隐含选择讲明白了，U-Boot 得写进裸区，拷一个文件进 boot 分区没用，Boot ROM 读 0x400 的时候，ext4 的目录项与 inode 它一个都不认，文件系统是 U-Boot 接手后才有的世界。

### 3 KiB 之后：本体落在哪，咱们验一步

头与 boot data 说了位置，U-Boot 本体从哪儿开始，咱们也验一步，不算白猜。入口 0x87800000 与 self 0x877ff400 差出 0xC00，照这个差数，文件第 0xC00 字节起的应该是 U-Boot 的正文。u-boot.bin 是没带头的那份裸正文，431144 字节，咱们把它的开头跟 .imx 第 0xC00 字节并排放在一起看：

```bash
# 主机 ~/imx-forge
xxd -l 16 /tmp/uboot-ref-evk/u-boot.bin
xxd -s 3072 -l 16 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

```text
00000000: b800 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
00000c00: b800 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
```

两行一字不差。咱们把开头这个字按小端拼一遍，0xea0000b8，ARM 里这是一条无条件跳转，跟着几条 ldr 指令把 PC 装上各自的向量地址，排成 U-Boot 的异常向量表，正文确实从 3 KiB 之后开始。前 3 KiB 是 Boot ROM 专用的头区，U-Boot 自己的字节从 0xC00 起头。

### EVK 与 AES 并排比：只有一个字不同

咱们再把 AES 板那份倒出来对一遍。

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

咱们把两份头摆在一起比，64 字节里只有一个字不同。0x24 起那四个字节，EVK 是 00 b0 06 00，AES 是 00 00 1a 00，小端读是 0x0006b000 对 0x001a0000，正是 boot data 里记镜像大小的那个字段。拿文件尺寸一核对就通：

```bash
# 主机 ~/imx-forge
ls -la /tmp/uboot-ref-evk/u-boot-dtb.imx /tmp/uboot-ref-aes/u-boot-dtb.imx
```

```text
-rw-r--r-- 1 charliechen charliechen 1702912 Nov 14 14:01 /tmp/uboot-ref-aes/u-boot-dtb.imx
-rw-r--r-- 1 charliechen charliechen  437248 Nov 14 14:01 /tmp/uboot-ref-evk/u-boot-dtb.imx
```

咱们把两个数各自加 0x400，EVK 的 437248 字节凑出 0x6b000，AES 的 1702912 字节凑出 0x1a0000，跟头里那个字一对，分毫不差。AES 板跟 EVK 板卡不同，配置不同，镜像大出将近四倍，头却几乎逐字节相同，差别只有镜像大小这一个字。这说明头格式是 Boot ROM 与 mkimage 之间的芯片级约定，不随板卡变。大小字差这么多，来源在正文，下一节拿源文件与日志说话。

## 四、DCD：Boot ROM 替咱们执行的初始化清单

咱们回到 EVK 转储的尾部。0x2C 起那四个字节 d2 01 e8 40，d2 是另一个标记，表示 DCD，Device Configuration Data，设备配置数据，01e8 是这份清单的长度，488 字节。清单的内容是一排寄存器写入，cc 01 e4 04 是写入命令的头，之后两两一组，前一个字是寄存器地址，后一个字是写进去的值，转储里第一组写的正是 0x020c4068 配 0xffffffff。

这对值有源文件，咱们把 AES 板的 imximage.cfg 开头翻出来：

```bash
# 主机 ~/imx-forge
sed -n '1,30p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
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

```

文件开头交代了格式与介质，IMAGE_VERSION 2 定镜像格式版本，BOOT_FROM 的分支没配 QSPI 也没配 NOR，落到 sd，注释里自己写着这一栏指的是启动设备。再往下就是 DCD 正文，咱们把正文开头几行拿出来：

```bash
# 主机 ~/imx-forge
sed -n '40,58p' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
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
```

咱们把两头的证据并排放：cfg 第 53 行 DATA 4 0x020c4068 0xffffffff，跟转储里第一组写入逐字符对上，第二组写的是 0x020c406c 配 0xffffffff，第 54 行照旧对上，往后每一组都能这么核。0x020c4068 是 CCM 的时钟门控寄存器 CCGR0，写 0xffffffff 是把外设时钟全部打开，后面配 DDR 才有得用，紧跟着几行把 CCGR 一组配平。0x021b 开头那一大段全是 DDR 控制器 MMDC 的寄存器，时序参数一行一行写进去，0x021b08 开头那一批是读写校准与延时参数，跟板上 DDR 颗粒的脾气一一相关，换颗粒就得换数。DDR 就是在这一段里活过来的，Boot ROM 把清单逐条执行完才跳进 0x87800000——U-Boot 的 C 代码一落地就要栈、要数据段，DDR 不提前配好，跳过去连放栈的地方都没有，配好了它才站得住。

个数咱们也拿真数对过。

```bash
# 主机 ~/imx-forge
grep -c '^DATA' third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
grep -c '^DATA' third_party/uboot-mainline/board/nxp/mx6ullevk/imximage.cfg
```

```text
61
60
```

咱们数出来，AES 板这份 cfg 顶格的 DATA 行 61 行，EVK 那份 60 行。AES 多出的那一行住在 #ifdef CONFIG_IMX_OPTEE 里（AES 的 cfg 第 61 行），out/uboot/.config 里没有 CONFIG_IMX_OPTEE 的 set 行，只有第 248 行的 CONFIG_IMX_OPTEE_DEK_ENCAP 留成 not set，真正进镜像的是 60 行。咱们算一遍，一行转成地址加值一对，占 8 字节，60 乘 8 是 480，加上两级命令头，正好凑成转储里那个清单长度 0x1E8，488 字节。行数、清单长度、转储里的标记，三头互相咬合。

板卡差异到底住在哪，咱们拿 diff 验一把，不空口下结论：

```bash
# 主机 ~/imx-forge
diff third_party/uboot-mainline/board/nxp/mx6ullevk/imximage.cfg third_party/uboot-mainline/board/nxp/mx6ull_aes_emmc/imximage.cfg
```

```text
3a4
>  * Copyright 2017 NXP
5c6
<  * Refer doc/imx/mkimage/imximage.txt for more details about how-to configure
---
>  * Refer doc/imx/mkimage/imximage.rst for more details about how-to configure
32c33
< PLUGIN	board/nxp/mx6ullevk/plugin.bin 0x00907000
---
> PLUGIN	board/nxp/mx6ull_aes_emmc/plugin.bin 0x00907000
58a60,64
> 
> #ifdef CONFIG_IMX_OPTEE
> DATA 4 0x20e4024 0x00000001
> CHECK_BITS_SET 4 0x20e4024 0x1
> #endif
```

结果值得咱们多看两眼。生效的寄存器写入一行都没差，diff 里多出的那条 DATA 住在没开的 OPTEE 分支里，两块板共同生效的 DATA 行完全一致，差出来的只有注释、文档名、PLUGIN 路径与 OPTEE 那一小段，AES 板这份 cfg 本就站在 EVK 的底子上，寄存器数原样沿用。原则没变，DDR 参数按板卡的颗粒与布线来，真换一块颗粒不同的板，这些 DATA 行就得一行一行重调，到那时 IVT 与头格式纹丝不动，动的只有这份清单与正文。镜像大出将近四倍的原因也在这儿，构建日志里 AES 那轮多编了 USB gadget、fastboot、显示这一批驱动，裸正文 1696688 字节对 EVK 的 431144 字节，头里那个大小字跟着正文长，头格式与清单数据纹丝没动。

清单长成数据的模样而不是代码，咱们琢磨一下就懂了。Boot ROM 只带一个极简的搬运器，条目格式得简单到不用解释器，一条固定 8 字节，地址一个字，值一个字，ROM 挨条取、挨条写就行。写成代码就得让它带编译器，还得对上指令集与版本，两头都重。编镜像时 mkimage 干的就是这个翻译活，把 DATA 行逐条转成 DCD 塞进镜像。cfg 里还有带校验的写法，CHECK_BITS_SET，写完要验指定位真的置上了，还有 PLUGIN 分支，把初始化交给一小段可执行代码去跑，连插件路径都写着各自板卡的目录名，参考配置没开 PLUGIN，走的是 DCD 这条路，boot data 里那一位是 0 也印证了。PLUGIN 行包在 cfg 开头的 #ifdef CONFIG_USE_IMXIMG_PLUGIN 里，EVK 那份在第 30 行，AES 那份在第 31 行，两轮构建的 .config 第 243 行都把它留成 not set，mkimage 走的是 #else 的 DCD 路。

本篇只立概念。清单怎么编、每个字段什么意思、DDR 参数怎么调，留给后面专门一篇，咱们到时拿今天认出的 d2 01 e8 40 当入口。

## 五、读到这里咱们知道了什么

咱们收一收。Boot ROM 靠 BOOT_MODE 分挡，按配置引脚或熔丝给出的次序挑介质，挑中谁就到谁的固定偏移找头，SD 与 eMMC 这一路的偏移是 1 KiB。头是 IVT，d1 开头的 32 字节索引卡，里面装着入口 0x87800000、DCD 的位置和它自己的落点，Boot ROM 认格式全凭这张卡。头后面拖着 DCD，Boot ROM 替咱们逐条执行，DDR 在这一段活过来，然后它跳进入口，把世界交给 U-Boot。

整条链咱们串成一根线，一眼看得全：

```text
上电
  -> Boot ROM 采样 BOOT_MODE 分挡，按配置引脚或熔丝的次序扫介质
  -> 在选中介质的 0x400 读 IVT，认 d1 开头的索引卡
  -> 照索引卡找到 DCD，逐条执行，DDR 活过来
  -> 照 boot data 把镜像就位，跳 0x87800000
  -> U-Boot 接手，往后才是文件系统的世界
```

介质上这几步是文件里验出来的，芯片里那几步是字段与手册互证的判读，这根线只是把它们接回原位。这一眼咱们自己还能再验，拿上一篇自家构建的产物跑同一句 xxd，头四个字节该是 d1 00 20 40，第二个字该是 0000 8087，尺寸字会随配置与版本浮动，标记和入口不会动。笔者在自己那份 out/uboot 上跑过，产物是 10 月 20 日那一轮，1702912 字节，头 64 字节跟 11 月 14 日编出的 AES 参考产物一字不差，隔了近一个月重编，头还是同一张脸：

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

真碰上烧完不活，咱们按今天认得的机制顺一遍再动手。模式先核，拨码拨的就是那组引脚电平，次序没落在烧的位置上，Boot ROM 扫完就静默。偏移再核，Boot ROM 只认 0x400，差一个扇区它读到的就不是 d1。头本身还要核，xxd 一眼，d1 00 20 40 缺哪个字都不合格。三样都过了，才轮得着怀疑镜像内容本身。

下一篇咱们把这张索引卡按字段过一遍，偏移、地址、每个零的来历都算给它看。

## 继续学习

- [EVK 与 AES 板的差别](../06_aes_vs_evk_diff.md)：本篇并排看的两份产物正是这两块板的构建，配置差在哪、移植路线怎么走，这一篇铺开。
- [SD 卡烧录实战](../../flash/09_sd_card_flashing.md)：上一篇交代了单烧 U-Boot 的写法，整卡镜像从生成到写卡的完整实测在这一篇。
