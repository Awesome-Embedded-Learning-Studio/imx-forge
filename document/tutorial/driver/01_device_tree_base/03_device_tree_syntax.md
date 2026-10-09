---
title: 语法速览：读懂本仓的 dts
---

# 03. 语法速览：读懂本仓的 dts

## 前言：兑现学习地图上的承诺

第 1 章画学习地图时咱们留过话：语法速览讲到你能独立读懂 `imx6ull-aes.dtsi` 为止。这一章就来兑现。真实工作里很少有人从零写一整份 dts，常态是拿到芯片厂的参考树，看懂它，在上面改。看懂所需要的语法其实不长：节点怎么命名，属性值有几种长相，`&` 引用是怎么回事，`#address-cells` 这类属性在数什么。这些咱们本章全部过完，例子一律取自本仓的真实文件。

语法全貌是另一回事。完整的属性规范、语法糖的细枝末节、dtc 内部怎么工作，本卷不碰，文末的深读块给你留了入口。速览的好处是学完马上能用：章末咱们把 `imx6ull-aes.dtsi` 从头到尾读一遍，读完后你应该找不出一行叫不出语法名目的代码。

## 动手：把主设备树编成 dtb，再拆回来

本章的教具咱们动真格的：把仓库的主设备树编成 dtb，再用 dtc 拆回 dts，源文件和产物对照着读。第 1 章说过编译分两阶段，C 预处理器把 `#include` 展平，dtc 再把展平结果编成 dtb。你自己的电脑上要有 `gcc` 和 `dtc`（Debian 系发行版装 `build-essential` 加 `device-tree-compiler`），另外把两个 submodule 初始化检出，再往内核树打上本仓补丁：

```bash
git submodule update --init third_party/linux_mainline third_party/uboot-imx
./scripts/apply_patches.sh linux_mainline
```

为什么必须打补丁，咱们看一眼编译目标就明白了。主设备树全文如下：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dts（全文）
// SPDX-License-Identifier: (GPL-2.0 OR MIT)
//
// Copyright (C) 2016 Freescale Semiconductor, Inc.

/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"
#include "imx6ull-14x14-evk-u-boot.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};

&clks {
	assigned-clocks = <&clks IMX6UL_CLK_PLL3_PFD2>,
			  <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
	assigned-clock-rates = <320000000>, <786432000>;
};

&csi {
	status = "okay";
};

&ov5640 {
	status = "okay";
};

/delete-node/ &sim2;

/*
	usdhc2 is assigned from arch/arm/dts/imx6ull-14x14-evk-emmc.dts
	which we simplified the include hieracy
*/
&usdhc2 {
	pinctrl-names = "default", "state_100mhz", "state_200mhz";
	pinctrl-0 = <&pinctrl_usdhc2_8bit>;
	pinctrl-1 = <&pinctrl_usdhc2_8bit_100mhz>;
	pinctrl-2 = <&pinctrl_usdhc2_8bit_200mhz>;
	bus-width = <8>;
	non-removable;
	status = "okay";
};
```

第一行 `/dts-v1/;` 是版本声明，每个 dts 开头都这么写。三行 include 就是第 1 章说过的分层：内核的 `imx6ull.dtsi` 描述芯片，本仓的 `imx6ull-aes.dtsi` 描述板卡，最后一个 `imx6ull-14x14-evk-u-boot.dtsi` 给 U-Boot 补配置。往后读你会看到，板级 dtsi 里引用了 `&sim2`，而主线内核已经把这个节点删掉了，本仓补丁把它补了回来。不打补丁，这个引用就是悬空的，编译一定失败。

咱们在仓库根目录执行编译：

```bash
gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I third_party/linux_mainline/arch/arm/boot/dts/nxp/imx \
    -I third_party/linux_mainline/include \
    -I third_party/uboot-imx/arch/arm/dts \
    -I driver/device_tree/alpha-board/linux \
    driver/device_tree/alpha-board/linux/imx6ull-aes.dts \
    -o /tmp/imx6ull-aes.pp.dts
dtc -I dts -O dtb -o /tmp/imx6ull-aes.dtb /tmp/imx6ull-aes.pp.dts
```

四条 `-I` 咱们挨个看过来。头一条到内核的 NXP imx 子目录找 `imx6ull.dtsi`。第二条到内核 `include/` 找 dt-bindings 头文件，芯片 dtsi 里 `#include <dt-bindings/clock/imx6ul-clock.h>` 这类尖括号包含全靠它，少了它，报错在 `imx6ul.dtsi` 的第 5 行就会出现。第三条最容易被漏掉。主 dts 还 include 了 `imx6ull-14x14-evk-u-boot.dtsi`，它不在内核树里，住在 uboot-imx 子模块的 `arch/arm/dts/` 下面，咱们为了它才把那个 submodule 也初始化。第四条指向板级目录，`imx6ull-aes.dtsi` 和主 dts 同目录，引号包含本来就能找到，写上它是对齐仓库构建脚本的口径。

编完咱们把 dtb 拆回 dts：

```bash
dtc -I dtb -O dts -o /tmp/imx6ull-aes.roundtrip.dts /tmp/imx6ull-aes.dtb
```

我在自己的电脑上跑通了这个链路，dtb 编出来 35903 字节，具体数值随树的内容变，不必对号。反编译出来的文件和源文件长得不像：label 全不见了，`&` 引用变成了数字，属性顺序也重排了。这些差异正是后面的教具，讲到 phandle 和覆盖时咱们回来对照。

## 节点：树与名字

设备树的本体是一棵树。根节点写作 `/`，其余节点一层层嵌套在里面，每个节点用花括号装自己的属性。咱们看板级文件的开头：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi（节选）
chosen {
	stdout-path = &uart1;
};

memory@80000000 {
	device_type = "memory";
	reg = <0x80000000 0x20000000>;
};
```

`chosen` 和 `memory@80000000` 都挂在根下。节点的名字有两种形态，光秃秃的名字，或者名字加 `@` 加地址。`memory@80000000` 的地址就是它 `reg` 里的首地址，`chosen` 不对应硬件，就没有 `@`。这个对应关系在读总线设备时更有用：后面你会碰到 `gt9147@5d`，`@` 后面的 5d 是触摸芯片在 I2C 总线上的从机地址，它 `reg` 里写的也是 `0x5d`，两边对得上，你就有理由相信这行没写错。

节点的名字前面还可以站一个 label，咱们看内核芯片级文件里的 GPIO 控制器，它就是标准长相：

```dts
// third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ul.dtsi（节选）
gpio1: gpio@209c000 {
	compatible = "fsl,imx6ul-gpio", "fsl,imx35-gpio";
	reg = <0x0209c000 0x4000>;
	gpio-controller;
	#gpio-cells = <2>;
};
```

`gpio1:` 是 label，给这个节点起的短名。没有它，你想指这个节点就得写完整路径 `/soc/bus@2000000/gpio@209c000`，又长又容易错，后面所有 `&gpio1` 的引用靠的都是这个短名。

还有一件事读树时值得放在心上：节点挂在谁下面，本身就是信息。挂在 I2C 控制器节点下面的 `gt9147` 是 I2C 从机，挂在 SPI 控制器下面的 `icm20608` 是 SPI 设备。本章后面会碰到的 `imx_aes_led` 挂在根下，反过来告诉你它不属于任何总线。

## 属性：值的几种长相

花括号里一行一个属性，属性就是键值对。值的几种长相，本仓文件里全有，咱们分类认一遍。

字符串最常见，`model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)"` 是本尊。一个属性也能装多个字符串，逗号隔开，根节点的 `compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull"` 就是字符串列表，内核拿它做驱动匹配时从前往后试。匹配机制留到平台设备驱动教程再展开，这里你认得出形态就行。

数值装在尖括号里，默认是 32 位无符号整数，十进制十六进制都行，一个属性可以装一串：背光的 `brightness-levels = <0 4 8 16 32 64 128 255>` 是八个亮度档位。个别属性要按字节读，写法换成 `/bits/ 8`，你在板级文件里能看到 `registers-default = /bits/ 8 <0x57>` 给 74hc595 移位寄存器设上电默认值，用的就是它。

最后一类属性压根没有值，你看到的就是一个名字站在那儿，`gpio-controller;` 就是。它的含义是“我是 GPIO 提供者”，出现即表态。

讲到这里得停一下，纠两个错。被这次重写替换掉的旧稿在“空属性”一节里写过“注意这些属性后面没有分号”，它只活在 git 历史里，你在现在的仓库里翻不到，可它自己贴的代码块里 `gpio-controller;` 的分号明明都在，说法和例子打架。哪个对？咱们不背书，拿 dtc 问。我编了个玩具 dts 专门验证，下面两段是造出来的，不是仓库文件：

```dts
// 玩具示例（造的，用来验证标点规则）
/dts-v1/;

/ {
	toy-node {
		my-flag
		another = "value";
	};
};
```

`my-flag` 后面咱们故意不放分号，块首那行标注不算进文件，报错行号对着没有它的版本数。dtc 的报错原文：

```text
Lexical error: toy-no-semicolon.dts:6.3-10 Unexpected 'another'
Error: toy-no-semicolon.dts:6.3-10 syntax error
FATAL ERROR: Unable to parse input tree
```

看行号，dtc 指的是第 6 行的 `another`，漏分号的 `my-flag` 在第 5 行。咱们排查 dts 时要提防这个错位：报错指到哪一行，嫌疑就往上一行查。把分号补上，同款文件编译就通过。属性一律以分号收尾，没有值的属性不例外，`gpio-controller;` 末尾那个分号一个都不能少，规则到此也就清楚了。

第二个错是分类。旧稿把 `#gpio-cells = <2>` 也算进了空属性，不对。你看它有等号有值，是正经的 32 位整数属性，含义是“引用我这个节点时，值里要跟两个数”。真正的空属性连等号都没有。两个属性在 gpio1 节点里紧挨着，分工完全不同，它们怎么配合，往下读 cells 和 phandle 你就看到了。

## 度量衡：#address-cells 与 #size-cells

`reg` 是咱们刚见过的“地址加长度”列表，但一份 `reg` 里几个数算地址、几个数算长度，规则写在父节点上。`#address-cells` 说地址占几个单元格，`#size-cells` 说长度占几个单元格，一个单元格就是一个 32 位整数。这组属性管的是孩子：子节点的 `reg` 怎么切，由父节点的度量衡决定。

根节点的度量衡是 1 加 1，写在内核 `imx6ul.dtsi` 的根上。咱们回看 `memory@80000000` 的 `reg = <0x80000000 0x20000000>`，读作：起始地址 0x80000000，长度 0x20000000，512MB 内存。

总线的度量衡常常不要长度。咱们看板级文件里那段 GPIO 模拟的 SPI，它自己声明了度量衡：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi（节选）
spi-4 {
	compatible = "spi-gpio";
	#address-cells = <1>;
	#size-cells = <0>;

	gpio_spi: gpio@0 {
		compatible = "fairchild,74hc595";
		reg = <0>;
	};
};
```

长度占零个单元格，孩子的 `reg = <0>` 就只剩一个片选号。网络那边的 mdio 是同款，`#address-cells` 为 1、`#size-cells` 为 0，底下 `ethernet-phy@2` 的 `reg = <2>` 是 PHY 在 MDIO 总线上的地址，咱们到章末还会遇到它。

带 `#` 的计数属性还有一串同姓的，`#gpio-cells`、`#pwm-cells`、`#interrupt-cells`。上面一对管 `reg` 的切分，这一串管的是别人引用我时，值里要跟几个参数。咱们看两个真实消费者：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi（节选）
pwms = <&pwm1 0 5000000 0>;
led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
```

`pwm1` 在内核 dtsi 里声明 `#pwm-cells = <3>`，所以 `&pwm1` 后面跟三个数：通道 0、周期 5000000 纳秒、标志 0。`gpio1` 的 `#gpio-cells = <2>`，`&gpio1` 后面跟两个数：引脚 3、标志。往后你读到陌生的引用，就去提供者节点数一下它声明的 cells，参数个数自然对上。

## phandle：引用在 dtb 里的真相

源文件里 `&gpio1` 是个名字，编进 dtb 之后它变成什么？咱们看反编译文件里的真实样子：

```dts
// /tmp/imx6ull-aes.roundtrip.dts（节选，dtc 反编译产物）
gpio@209c000 {
	compatible = "fsl,imx6ul-gpio", "fsl,imx35-gpio";
	reg = <0x209c000 0x4000>;
	gpio-controller;
	#gpio-cells = <0x02>;
	interrupt-controller;
	#interrupt-cells = <0x02>;
	phandle = <0x09>;
};

imx_aes_led {
	compatible = "imxaes,led";
	pinctrl-names = "default";
	pinctrl-0 = <0x4a>;
	status = "okay";
	led-gpio = <0x09 0x03 0x01>;
};
```

你看，两个 0x09 对上了。gpio1 节点身上多出一个源文件里没有的属性 `phandle = <0x09>`，引用它的 `led-gpio` 里写的头一个数也是 0x09。dtc 编译时给每个被引用的节点编一个号，把 `&gpio1` 替换成这个号，号就是 phandle。后面的数原样跟着：03 是引脚号，01 是标志。源文件里写的 `GPIO_ACTIVE_LOW` 是个宏，预处理那一步把它换成了 1，定义住在内核 `include/dt-bindings/gpio/gpio.h`。

具体的编号值每次编译都可能变，0x09 不必记，要看住的是关系：引用变数字，数字指回被引用的节点。`/proc/device-tree` 是板子上内核把 dtb 展开出的那棵树，你对 `/proc/device-tree/imx_aes_led/led-gpio` 做 `hexdump -C`，看到的正是 led-gpio 的三个数，一共十二个字节。

反编译文件里还有两处变化值得咱们认。`chosen` 里源文件写的 `stdout-path = &uart1`，产物里变成了完整路径：

```dts
// /tmp/imx6ull-aes.roundtrip.dts（节选）
chosen {
	stdout-path = "/soc/bus@2000000/spba-bus@2000000/serial@2020000";
};
```

`&label` 用作属性值时，dtc 把它解析成节点的完整路径字符串。`aliases` 是内核 `imx6ul.dtsi` 开头的一张表，给常用外设起短名，里面 `ethernet0 = &fec1` 这类条目在产物里也全成了路径串，咱们碰到的是同一个机制。另一处是 label 本身：源文件里的 `gpio1:`、`pinctrl_uart1:`，你在产物里一个都找不到。label 只活在源文件里，是写给人看、写给 `&` 引用用的记号，dtb 不需要它。

## 引用与覆盖：在同一棵树上打补丁

读到这里你可能已经察觉，板级文件几乎不新建树，它在内核铺好的树上打补丁。补丁在这儿是打比方，跟动手一节里 `apply_patches.sh` 打的补丁文件是两码事，说的是往既有树上叠修改的写法。语法就是 `&label { }`：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi（节选）
&uart1 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_uart1>;
	status = "okay";
};
```

内核 `imx6ul.dtsi` 里 uart1 默认 `status = "disabled"`，芯片级文件不知道你这块板用哪个串口，干脆都关上。板级文件把同一个属性再写一遍，值换成 `okay`。谁赢？预处理器把 include 展平成一份长文件，dtc 从上到下读，同一属性最后一次写入生效。覆盖还能叠好几层：摄像头 `ov5640` 在板级 dtsi 里写的是 `disabled`，主 dts 又把它翻成 `okay`，两级方向相反，后写的赢。你以后排查“属性到底是谁定的”，就沿着 include 链一层层找同名属性，离你最近的一处说了算。

能加能改，还能删，咱们看两个真实行：

```dts
// driver/device_tree/alpha-board/linux/imx6ull-aes.dts（节选）
/delete-node/ &sim2;

// driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi（节选）
&ecspi3 {
	/delete-property/ dmas;
	/delete-property/ dma-names;
};
```

`/delete-node/` 把整个节点从树里拿掉，主 dts 对 sim2 干的就是这个。`/delete-property/` 只拿属性：ECSPI3 让 ICM20608 用，原来的 DMA 配置不要了。删没删干净，咱们拿反编译文件验证。`&ecspi3` 编进产物后它的节点就叫 `spi@2010000`，`@` 后面的数正是它的基址，这个节点里通篇找不到 dmas，而没被动过的 `spi@2014000` 还带着它的 `dmas = <...>`，一对比就清楚。

引用不一定非走 label，走路径也行。U-Boot 侧的 dtsi 里有现成例子，全文贴给你：

```dts
// third_party/uboot-imx/arch/arm/dts/imx6ull-14x14-evk-u-boot.dtsi（全文）
// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright 2022-2023 NXP
 */

&{/aliases} {
	spi0 = &qspi;
	spi1 = &ecspi1;
	spi2 = &ecspi2;
	spi3 = &ecspi3;
	spi4 = &ecspi4;
};

&pinctrl_uart1 {
	bootph-all;
};

&rngb {
	bootph-all;
};
```

`&{/aliases}` 花括号里放的是节点路径，目标没有 label 时就这么指。`bootph-all` 这类属性是 U-Boot 的启动阶段标记，含义归 U-Boot 教程讲，咱们这里只认语法。你注意一下它用的正是路径引用：aliases 节点没有 label，想改它只有走路径。

最后咱们换个角度看 `imx6ull.dtsi`：它整份干的就是这套补丁活。开头 include `imx6ul.dtsi`，往后全在引用并修改它铺好的树：

```dts
// third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/imx6ull.dtsi（节选）
#include "imx6ul.dtsi"
#include "imx6ull-pinfunc.h"
#include "imx6ull-pinfunc-snvs.h"

/* Delete UART8 in AIPS-1 (i.MX6UL specific) */
/delete-node/ &uart8;

&cpu0 {
	clock-frequency = <900000000>;
};
```

内核自己的注释写着“删掉 6UL 特有的 UART8”，芯片之间的差异用 `/delete-node/` 表达。主频 900MHz，用 `&cpu0` 覆盖。咱们看懂这个，板级文件的写法就不神秘了：从芯片到板卡，整棵树是一层层增量叠出来的，每一层都在引用上一层。

## 把 imx6ull-aes.dtsi 从头读一遍

教具和语法都齐了，咱们把目标文件过一遍。它分两大块：根节点 `/` 里新建的一串节点，和后面一长串 `&` 覆盖。

咱们把根下的新节点过一遍。`chosen` 定控制台，`stdout-path` 指向 uart1。`memory` 报 512MB 内存。`reserved-memory` 给 CMA 预留了 160MB（CMA 是内核预留出来的一大块连续内存），`size = <0xa000000>` 算出来就是它，里面还有一行空的 `ranges;`，一句话交代：空 ranges 表示子地址不经翻译直接当物理地址用，本仓碰到的 ranges 全是空的，非空的地址翻译归深读路线。`backlight` 和 `panel` 管屏幕，`panel-timing` 里那串时序参数的数值照屏幕的数据手册填，字段语义归深读路线。再往下几颗 `regulator-*` 是固定稳压器，`sound-wm8960` 是声卡，`audio-routing` 那一长串字符串列表，描述的是耳机孔、扬声器到 codec 引脚的接线路由。`spi-4` 你已经认识了。最后三个 `imx_aes_led`、`beep`、`key-gpio` 是教程自己的外设，注释写明从哪些章起默认启用。

`&` 覆盖块的主题是外设使能，咱们把主要的过一遍。`uart1`、`i2c1`、`i2c2`、`fec1`、`fec2`、`can1`、`qspi`、`sai2`、`usdhc1`、`usdhc2`、`lcdif`、`pwm1`，套路一致，都是给 `pinctrl-0`，把 `status` 翻成 `okay`。少数反着来：`uart2` 和 `can2` 被显式写成 `disabled`，注释交代了缘由，引脚让给 ECSPI3 上的 ICM20608。`i2c2` 下面挂着触摸芯片 `gt9147@5d` 和摄像头 `ov5640@3c`，`fec2` 下面挂着 `mdio` 和两颗 PHY，都是总线节点下挂从设备的实例。`gpio_spi` 里还有两个 `gpio-hog` 子节点，开机就把网口 PHY 的复位脚拉高，hog 的细节本卷不展开，归深读路线。没逐个点到的 `pxp_v4l2`、i2c1 底下的 `ap3216c` 和 `wm8960`，还有覆盖块里剩下的条目，用的也是这几套语法，你通读时自己对得上。

最大的一块是 `&iomuxc`，几十个 `pinctrl_xxx` 组，每组一个 `fsl,pins` 列表，左边宏写引脚复用，右边十六进制写电气参数。这是引脚复用的地盘，[引脚复用教程](../02_pinctrl_gpio/index.md)整章讲它，你在这里只要认得出 `pinctrl-0 = <&pinctrl_uart1>` 引用的是 `&iomuxc` 下面哪个组就行。

到这里收个尾。你现在再打开 `imx6ull-aes.dtsi`，应该没有一行你叫不出语法名目。属性值的语义拿不准，去[设备树配置指南](../../../modules/DEVICE_TREE_GUIDE.md)按外设查，它是本仓的参考手册，LCD、网络、存储的配方都在里面。

## 常见卡点

**漏了分号，报错指向下一行。** 前面的玩具实验演示过，dtc 把错误标在漏分号那一行的下一个属性上。看到 `syntax error` 又找不出哪里错，你就拿上一行查分号。

**`-I` 缺一条，两种报错模样。** 少了内核 `include/`，预处理器停在 `imx6ul.dtsi`，报 `fatal error: dt-bindings/clock/imx6ul-clock.h: No such file or directory`。少了 uboot-imx 的 `arch/arm/dts`，停在主 dts 第 9 行，报 `fatal error: imx6ull-14x14-evk-u-boot.dtsi: No such file or directory`。报错都带文件名，你缺哪条 `-I` 补哪条。

**没打补丁，sim2 找不到。** dtc 报 `Label or path sim2 not found`，位置指到板级 dtsi 的 `&sim2`。主线内核删了这个节点，本仓补丁补回来的，你回动手一节把 `./scripts/apply_patches.sh linux_mainline` 跑上就好。

**想改芯片级内容，动了 imx6ull.dtsi。** 它在 submodule 的内核树里，你动了就把内核树弄脏，补丁也打不回去了。改法永远是板级文件里 `&` 引用覆盖，[板级修改一章](09_board_dts_modification.md)会把这个流程走完整。

## 下一步

语法这一关过了，读树的活儿练完了。下一章[驱动改造](08_device_tree_driver.md)咱们换镜头：拿仓库里真实的 `led_hw.c` 开刀，从抄死的寄存器地址改成运行时去设备树里取，一路走到板子上点灯。改树本身的完整流程，加节点、编译、部署、验证，再往后的[板级修改一章](09_board_dts_modification.md)等着你。

::: details 深读：语法全貌与 dtc 内部
本章只取了读懂本仓 dts 所需的语法段。完整的属性规范、`ranges` 的地址翻译、dtc 的内部行为与告警体系，连同前面归到深读路线的 `panel-timing` 字段语义和 hog 细节，咱们把这些放进独立的设备树原理仓库逐章拆解，本卷链接待该仓库篇目定稿后接入。
:::
