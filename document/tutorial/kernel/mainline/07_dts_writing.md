---
title: 设备树：从参考板改出 AES 板
---

# 设备树：从参考板改出 AES 板

> 本篇解决一件事：手里有一棵主线内核和一块正点原子的 AES 板，怎么让内核认识板上的每一颗芯片。咱们从内核树自带的参考板出发，先读懂设备树到底是什么，再盘清板上的硬件清单，最后在您自己的树里亲手造出板级设备树文件对，并注册给构建系统。上一篇 [内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md) 收了配置的尾，本篇补上硬件描述这一半；编出 zImage 与 dtb、把第一颗外挂模块也编出来、在 QEMU 里首启闯 15 项断言验收，交给下一篇 [编译、外挂模块与 QEMU 首启验收](./08_dts_build_boot.md) 收官。

::: tip 前置知识·环境
- 前置章：[内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md)、[取源码：从 stable 树拉下 v7.2.9](./03_source_fetch.md)、[从零开始搭建主线内核编译环境](./02_env_setup.md)、[BSP vs 主线对比](./04_bsp_vs_mainline.md)
- 源码树 ~/experiments/linux-mainline（v7.2.9），构建目录 ~/experiments/linux-build（两目录制见 05 篇）
- 本篇只写板级设备树源文件并注册给构建系统，不碰编译；编产物与首启验收在下一篇
- 交叉工具链 arm-none-linux-gnueabihf-（Arm GNU Toolchain 15.2.Rel1）
:::

## 内核眼里的硬件清单：设备树到底是什么

同一个 zImage，凭什么能跑在 NXP 官方 EVK 上，也能跑在正点原子的板子上？咱们把镜像和板子的关系想清楚，答案就出来了：镜像本身不认识任何一块具体的板子，它只认识随镜像一起交给引导程序的那份硬件清单。这份清单就是设备树：文本格式，描述板上有多少内存、串口控制器在哪个物理地址、wm8960 挂在哪条 I2C 总线的哪个地址。内核启动时解析清单，拿每个节点去匹配驱动，compatible 对上了、资源齐了，设备才活。清单写错一个字节，轻则设备失踪，重则整机停在启动早期，而且往往一声不吭。

移植的方法论可以压成一句话：参考板 + 硬件差异清单。SoC 厂商在内核树里为每颗芯片维护参考板，它的 SoC 部分与咱们的板子完全同源，能复用的占九成，板级部分才是差异所在。于是任何一块新板子的移植都走同一条路：选一块合适的参考板，盘清自家板子和它的差异，再把差异逐个写成设备树节点。本篇就在您的树里把这条路完整走一遍。

## 参考板选 imx6ull-14x14-evk：同芯、官方维护、就在树里

为什么是它？咱们直接看内核树里这个文件本身。

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
cat arch/arm/boot/dts/nxp/imx/imx6ull-14x14-evk.dts
```

```dts
// SPDX-License-Identifier: (GPL-2.0 OR MIT)
//
// Copyright (C) 2016 Freescale Semiconductor, Inc.

/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ul-14x14-evk.dtsi"

/ {
	model = "Freescale i.MX6 UltraLiteLite 14x14 EVK Board";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};

&clks {
	assigned-clocks = <&clks IMX6UL_CLK_PLL3_PFD2>;
	assigned-clock-rates = <320000000>;
};
```

这个文件短得让人意外：除时钟树外什么都没配。原因是结构分层：控制器实体都在 `imx6ul.dtsi` 里，它描述 SoC 本身（CPU、中断控制器、全部外设控制器的寄存器地址）；`imx6ull.dtsi` include `imx6ul.dtsi` 之后做 6ULL 的增量覆盖：删掉 6UL 才有、6ULL 没有的 uart8 和 crypto，再补上 6ULL 自己的东西：新开一条 AIPS3 总线放 dcp、rngb、iomuxc_snvs 和新地址的 uart8，并覆盖 cpu0 频率表与 ocotp/pxp/usdhc 的 compatible；`imx6ul-14x14-evk.dtsi` 描述参考板的板级外设，真正的板级入口文件只做增量。咱们选它当参考板：AES 板用的是同一颗 i.MX6ULL，SoC 层原样复用；它由 NXP 在主线持续维护，不挑内核版本；它就在树里，编 dtb 顺手就能出来对照。

但亲缘归亲缘，照抄必翻车。AES 板出自正点原子 alpha 系，虽然参考过 NXP 的设计，外设布局已经岔开：音频 codec 实测挂在 I2C1 而非 EVK 的 I2C2，触摸、光照传感器、六轴 IMU 是教程自家的器件，屏幕是 1024x600 的七寸屏、时序与 EVK 面板不同，CAN2 和 UART2 的引脚还让给了 SPI。差异清单不盘清楚，抄来的节点就是一堆编译通过、硬件不认的空配置，笔者在早期移植稿里吃过的亏不止一回。

## 盘点 AES 板：对着 dtsi 列硬件清单

动手之前，咱们把板上的硬件一次盘完。本篇采用的讲法是先看成品再拆做法：板级文件对（imx6ull-aes.dts 与 imx6ull-aes.dtsi）就是本篇的产出，下面先拿探针把它扫一遍，明白里面有什么，后面的节点精读逐个讲这些内容怎么写出来、写错会怎样。探针是 grep，不靠记忆：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
/usr/bin/grep -n 'gt9147\|wm8960\|ap3216c\|icm20608' arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi
```

```text
 98:		 * - wm8960 audio codec
128:	sound-wm8960 {
129:		compatible = "fsl,imx-audio-wm8960";
130:		model = "wm8960-audio";
221:	gt9147: gt9147@5d {
222:		compatible = "goodix,gt9147", "goodix,gt9xx";
335:	ap3216c@1e {
336:		compatible = "imxaes,ap3216c";
341:	codec: wm8960@1a {
343:		compatible = "wlf,wm8960";
416:	icm20608@0 {
417:		compatible = "imxaes,icm20608";
```

对照文件实文，咱们把 AES 板的硬件清单列成一张表：

| 硬件 | 设备树挂点 | 要点 |
|---|---|---|
| 512MB 内存 | `/memory@80000000` | `reg = <0x80000000 0x20000000>` |
| 调试串口 | `&uart1` | `chosen` 的 `stdout-path` 指向它 |
| SD 卡 | `&usdhc1` | `cd-gpios` 用 GPIO1_IO19 做插拔检测 |
| eMMC | `&usdhc2` | 8bit 总线，`non-removable` |
| 双网口 | `&fec1` `&fec2` | mdio 挂两颗 KSZ8081，PHY 地址 2 和 1 |
| 光照/距离传感器 | `&i2c1` 下 `ap3216c@1e` | 教程器件，地址 0x1e |
| 音频 codec | `&i2c1` 下 `wm8960@1a` | 实测在 I2C1 0x1a，不在 EVK 的 I2C2 |
| 电容触摸 | `&i2c2` 下 `gt9147@5d` | GT911，中断 GPIO1_IO09，复位 GPIO1_IO05 |
| 六轴 IMU | `&ecspi3` 下 `icm20608@0` | 复用 UART2 四根引脚，片选 GPIO1_IO20 |
| RGB LCD | `&lcdif` + `panel-dpi` | 1024x600，时序在 `panel-timing` |
| 背光 | `pwm-backlight` | `pwms = <&pwm1 0 5000000 0>` |
| CAN | `&can1` | can2 关闭，引脚让给 ECSPI3 |
| USB | `&usbotg1` `&usbotg2` | 一个 otg、一个 host |
| QSPI Flash | `&qspi` 下 `flash@0` | `micron,n25q256a` |
| LED/蜂鸣器/按键 | `imx_aes_led` `beep` `key-gpio` | 教程自写驱动的节点 |

这里得停下提醒一句：您给自己板子做移植时，这一节要对着原理图做，不能对着别人的清单做。哪颗器件挂哪条总线、地址是多少、复位脚接在哪，原理图说了算，探针和清单只是核对手段。这一步偷懒，后面每个节点都在裸奔。

## 文件骨架的两种写法：&label 改写与全新节点

板级设备树全篇只有两种写法，咱们先把骨架看清。一种是 `&label` 引用改写：SoC dtsi 已经把控制器的寄存器地址、中断号写好了，板级文件用 `&uart1` 这样的标签引用节点，补上引脚配置和 `status = "okay"`。另一种是全新节点：器件不长在 SoC 上（I2C/SPI 子设备、面板、电源调节器），直接在板级文件里写出来。

哪些 label 被改写了，咱们拿一条 grep 就能画出全图导览：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
/usr/bin/grep -n '^&' arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtsi
```

```text
200:&clks {
205:&csi {
215:&i2c2 {
256:&fec1 {
265:&fec2 {
296:&can1 {
303:&can2 {
311:&gpio_spi {
327:&i2c1 {
353:&lcdif {
369:&pwm1 {
375:&pxp {
379:&qspi {
395:&sai2 {
407:&ecspi3 {
423:&snvs_poweroff {
427:&snvs_pwrkey {
431:&tsc {
440:&uart1 {
446:&uart2 {
461:&usbotg1 {
468:&usbotg2 {
474:&usbphy1 {
478:&usbphy2 {
482:&usdhc1 {
494:&usdhc2 {
503:&wdog1 {
509:&iomuxc {
```

咱们数一数，28 个 label，每个后面就是这块板子对 SoC 默认配置的修改。注意里面有 `&can2` 和 `&uart2`，它们的 `status` 是 `disabled`：这两组引脚让给 ECSPI3 的决定就落在板级文件里。上游 `imx6ul.dtsi` 里这俩节点本来就写着 `disabled`，SoC 默认就没启用，板级再显式写一遍，是把这个决定和引脚改落的 pinctrl 写在一处，防止后续 include 变动悄悄把它们启用。icm20608 复用的四个 pad 正是 UART2 的 TX、RX、RTS、CTS。

引脚复用走 pinctrl，咱们把它当纪律记：pad 的复用与电气配置写成宏加十六进制值；分组按功能起名，一个外设一组；外设节点里用 `pinctrl-names` 和 `pinctrl-0` 引用组。拿 icm20608 的引脚组当例子：

```dts
pinctrl_ecspi3: ecspi3grp {
	fsl,pins = <
		MX6UL_PAD_UART2_TX_DATA__GPIO1_IO20   0x10b0  /* CS   */
		MX6UL_PAD_UART2_RX_DATA__ECSPI3_SCLK  0x10b1  /* SCLK */
		MX6UL_PAD_UART2_RTS_B__ECSPI3_MISO    0x10b1  /* MISO */
		MX6UL_PAD_UART2_CTS_B__ECSPI3_MOSI    0x10b1  /* MOSI */
	>;
};
```

咱们拆开看 `MX6UL_PAD_UART2_RX_DATA__ECSPI3_SCLK` 这种宏：它说的是这个物理引脚（UART2_RX_DATA 那个 pad）这次复用为 ECSPI3 的 SCLK 功能。后面的 `0x10b1` 是 pad 的电气配置（上拉、驱动强度、速率），位含义在 i.MX6ULL 参考手册的 IOMUXC 一章。复用宏写错，轻则设备无响应，重则两个驱动抢同一个 pad，内核报 pin already requested。

## 五个代表节点精读

全篇节点几十个，逐个念完既没重点也记不住。咱们挑五个写法与踩坑点各不相同的，看懂它们，剩下的照葫芦画瓢。

### usdhc1：SD 卡，第一个完整的节点

```dts
&usdhc1 {
	pinctrl-names = "default", "state_100mhz", "state_200mhz";
	pinctrl-0 = <&pinctrl_usdhc1>;
	pinctrl-1 = <&pinctrl_usdhc1_100mhz>;
	pinctrl-2 = <&pinctrl_usdhc1_200mhz>;
	cd-gpios = <&gpio1 19 GPIO_ACTIVE_LOW>;
	keep-power-in-suspend;
	wakeup-source;
	vmmc-supply = <&reg_sd1_vmmc>;
	status = "okay";
};
```

咱们逐行看。`pinctrl-names` 配合三个 `pinctrl-<n>` 是高速 SD 的典型三态写法：低速初始化，协商到 100MHz、200MHz 后内核自动切换到对应的引脚电气组（后两组把驱动强度调高）。`cd-gpios` 声明插拔检测脚，SD 卡座的热插拔靠它，`GPIO_ACTIVE_LOW` 表示插卡时引脚为低。`vmmc-supply` 指向一个固定电压调节器节点（本板是 `reg_sd1_vmmc`，3.3V），内核按它先给卡供电再初始化。`status = "okay"` 是总开关，SoC dtsi 里默认 `disabled`，没有这一行整个节点不出场。

pinctrl 组里还有个细节值得您看一眼：检测脚用的是 `MX6UL_PAD_UART1_RTS_B__GPIO1_IO19`，也就是把 UART1 的 RTS 脚复用成了 GPIO，SD 卡座并没有专用 pad。i.MX6ULL 的 pad 就这么点，复用是常态，拼的就是那张对照表。

### i2c1 上的 wm8960：子设备怎么挂上总线

```dts
&i2c1 {
	clock-frequency = <100000>;
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_i2c1>;
	status = "okay";

	/* 教程 AP3216C（IR/ALS/PS），替代原 EVK 的 mag3110/fxls8471 */
	ap3216c@1e {
		compatible = "imxaes,ap3216c";
		reg = <0x1e>;
	};

	/* WM8960 实测在 I2C1 @0x1a（非原 EVK 的 I2C2；原版 patch/BSP 此处写错）*/
	codec: wm8960@1a {
		#sound-dai-cells = <0>;
		compatible = "wlf,wm8960";
		reg = <0x1a>;
		wlf,shared-lrclk;
		wlf,hp-cfg = <3 2 3>;
		wlf,gpio-cfg = <1 3>;
		clocks = <&clks IMX6UL_CLK_SAI2>;
		clock-names = "mclk";
	};
};
```

咱们看这个节点：I2C 控制器是 `&label` 改写，子设备是全新节点，两种写法同框。子设备的 `reg` 就是器件的 I2C 地址，`wm8960@1a` 的 `@1a` 后缀与 `reg = <0x1a>` 必须一致。这条 unit_address_vs_reg 检查在内核编 dtb 时默认被关着，要看它报警得开 W=1 或裸跑 dtc，写节点的时候纪律照守。`compatible = "wlf,wm8960"` 拿去和内核 I2C 驱动表的 of_match 匹配，对上才 probe。`#sound-dai-cells = <0>` 说明这个节点会被音频链路当 DAI 引用：板级文件里的 `sound-wm8960` 声卡节点用 `audio-codec = <&codec>` 指过来，`codec:` 这个标签就是给它用的。

这块板上有个真坑：EVK 参考设计把 codec 放在 I2C2，早期移植稿照抄了，实际的板子上实测它在 I2C1 的 0x1a，笔者把这次纠错留在了 dtsi 的注释里。地址这种事，i2cdetect 扫一遍就知道，别信参考板。

### lcdif、panel 与背光：三者怎么咬合

显示是全篇最绕的一组，咱们把它拆开看，难在它是一条链：控制器 lcdif 按面板要求的时序把像素搬出去，面板 panel-dpi 声明这套时序长什么样，背光 pwm-backlight 负责把屏幕照亮。

```dts
backlight_display: backlight-display {
	compatible = "pwm-backlight";
	pwms = <&pwm1 0 5000000 0>;
	brightness-levels = <0 4 8 16 32 64 128 255>;
	default-brightness-level = <6>;
	status = "okay";
};

panel: panel-dpi {
	compatible = "panel-dpi";
	backlight = <&backlight_display>;
	width-mm = <154>;
	height-mm = <86>;

	panel-timing {
		clock-frequency = <51200000>;
		hactive = <1024>;
		vactive = <600>;
		hfront-porch = <160>;
		hback-porch = <140>;
		hsync-len = <20>;
		vback-porch = <20>;
		vfront-porch = <12>;
		vsync-len = <3>;
		hsync-active = <0>;
		vsync-active = <0>;
		de-active = <1>;
		pixelclk-active = <0>;
	};

	port {
		panel_in: endpoint {
			remote-endpoint = <&lcdif_out>;
		};
	};
};

&lcdif {
	assigned-clocks = <&clks IMX6UL_CLK_LCDIF_PRE_SEL>;
	assigned-clock-parents = <&clks IMX6UL_CLK_PLL5_VIDEO_DIV>;
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_lcdif_dat &pinctrl_lcdif_ctrl>;
	status = "okay";

	port {
		lcdif_out: endpoint {
			remote-endpoint = <&panel_in>;
		};
	};
};
```

`panel-timing` 里的十三个数就是屏幕手册里那行时序参数，咱们抄的时候一个都不能错：像素时钟 51.2MHz，有效区 1024x600，前后廊与同步脉宽共同拼出每行的完整周期。`clock-frequency` 写错了不报错，屏幕花屏或干脆不亮。背光挂在 PWM1 上，周期 5 毫秒，`brightness-levels` 给出八档亮度，开机即取第 6 档；panel 用 `backlight = <&backlight_display>` 把背光绑在自己身上，DRM 框架使能面板时顺手开背光。

两个 `port`/`endpoint` 互相用 `remote-endpoint` 指向对方，这是内核图形子系统的标准连线写法：控制器是源头，面板是终点，内核沿这条边把 lcdif 和 panel-dpi 驱动拼成一条显示链。咱们写漏任何一个方向，probe 时两边都报找不到对端。

### fec 与 mdio：双网口的 PHY 编址

```dts
&fec2 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_enet2 &pinctrl_enet2_reset>;
	phy-mode = "rmii";
	phy-handle = <&ethphy1>;
	phy-supply = <&reg_peri_3v3>;
	status = "okay";

	mdio {
		#address-cells = <1>;
		#size-cells = <0>;

		ethphy0: ethernet-phy@2 {
			compatible = "ethernet-phy-id0022.1560";
			reg = <2>;
			micrel,led-mode = <1>;
			clocks = <&clks IMX6UL_CLK_ENET_REF>;
			clock-names = "rmii-ref";
		};

		ethphy1: ethernet-phy@1 {
			compatible = "ethernet-phy-id0022.1560";
			reg = <1>;
			micrel,led-mode = <1>;
			clocks = <&clks IMX6UL_CLK_ENET2_REF>;
			clock-names = "rmii-ref";
		};
	};
};
```

咱们把编址规则看明白：两颗 PHY 都挂在 fec2 的 mdio 总线（管理总线）上，`reg` 是它们在这条总线上的地址，2 和 1，接线决定的，原理图说了算。`ethphy0/ethphy1` 两个标签分别被 `fec1` 与 `fec2` 的 `phy-handle` 引用，控制器靠它认领自己那颗 PHY。`compatible = "ethernet-phy-id0022.1560"` 直接写硬件 ID（0x0022 是 Micrel 厂商号，0x1560 是 KSZ8081 型号），比让内核读寄存器自识别更早定驱动。`phy-mode = "rmii"` 声明与 PHY 的数据接口是两线制 RMII。这颗 PHY 还给咱们留了一个关于 MAC 地址的坑，放到下一篇验收一节说。

### ecspi3 与 icm20608：SPI 子设备的 reg 与频率

```dts
&ecspi3 {
	/delete-property/ dmas;
	/delete-property/ dma-names;
	fsl,spi-num-chipselects = <1>;
	cs-gpios = <&gpio1 20 GPIO_ACTIVE_LOW>;
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_ecspi3>;
	status = "okay";

	icm20608@0 {
		compatible = "imxaes,icm20608";
		spi-max-frequency = <8000000>;
		reg = <0>;
	};
};
```

咱们先记住一个区别：SPI 子设备的 `reg` 和 I2C 完全两码事：I2C 的 `reg` 是器件地址，SPI 的 `reg` 是片选编号，`reg = <0>` 配合上面的 `cs-gpios`，表示用 GPIO1_IO20 这根 GPIO 当第 0 个片选。`spi-max-frequency = <8000000>` 是访问这颗器件的频率上限，ICM20608 的手册给的就是 8MHz，超了就写错数。`/delete-property/ dmas` 是板级文件修改 SoC 默认属性的语法：把 imx6ul.dtsi 里 ecspi3 自带的 DMA 通道声明删掉，驱动走 PIO 传输，QEMU 日志里那条 -ENODEV 报 DMA 通道的错误也因此无害。

## 三段战史：死代码、双轨地址与一根脚的两个主人

这批文件不是一次写对的，重写时笔者把继承来的配置重新过了一遍，加上这次首启翻的车，挖出三段战史，都有教学价值，值得单独一节。

### sim2：四件东西互相抵消，净效果为零

旧稿里 sim2 一共牵扯四件东西：旧补丁往 SoC 层的 imx6ul.dtsi 里补了一个 sim2 控制器节点；板级 dtsi 里跟着写了一个 &sim2 激活块，status = "okay"，pinctrl-0 引着引脚组；iomuxc 里躺着配套的 pinctrl_sim2 组；板级 dts 末尾却又来了一条 /delete-node/ &sim2;，把整棵节点连引用一起送走。单看每一件都像有用，放在一起看，净效果是零：前三件搭好的东西，第四件原地拆掉。更尴尬的是，v7.2.9 上游的 imx6ul.dtsi 里根本没有 SIM 控制器节点，笔者拿 grep 对着上游扫过，`sim@` 一个都搜不出来。旧补丁当年补 sim2 是对着更老的内核树做的，上游后来重组了文件，补丁的假想敌已经不存在了。

死代码本身不咬人，但它教会咱们怎么发现死代码，这个方法比结论值钱：编译产物是唯一算数的东西，源码里写了什么不作数。

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
~/experiments/linux-build/scripts/dtc/dtc -I dtb -O dts \
    ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | grep -c sim2
```

```text
0
```

咱们把编出来的 dtb 反编译再数一遍，sim2 出现零次。节点在最终产物里不存在，围绕它的 pinctrl、补丁叙事就全是空转。这次从零重写把四件全部删除，编译照常通过，QEMU 照常起机——这就是死代码的定义：删掉它，世界没有任何变化。

### GT9147 的 0x5d 与 0x14：双轨分歧要白纸黑字

GT9147 这段战史更微妙，您盯着 dts 里那个 0x5d 看半天也不会觉得它有问题。板级 dts 把 GT9147 写在 I2C2 的 0x5d，而实际的板子上实测这颗触摸在 0x14。0x5d 不是笔误：QEMU 的 gt911 模型把地址硬编码在 0x5d，下一篇验收断言里的 gt911-probe 依赖它；实际的板子那侧的验证走驱动篇触摸章自己的板级 dts，写 0x14。同一颗芯片、两套环境、两个地址，这个分歧记录在本篇配套的说明文件里，修复排在 QEMU 的 gt911 模型支持改地址之后。

教训值得您带走：一套配置同时伺候模拟器和实际的板子时，任何分歧都必须白纸黑字写下来，写在哪、为什么、打算什么时候了结。不写下来，半年后没人记得 0x5d 是故意的，看起来就像 bug，然后有人在实际的板子上调三天触摸没反应。下一篇验收节您会看到 `Goodix-TS 1-005d` 的日志，那就是 QEMU 侧的 0x5d 在说话。

### GPIO1_IO09：一根脚的两个主人

第三段是咱们这次从零首启当场翻的车，最能说明"节点对了，板子照样不认"是怎么回事。QEMU 起机后 15 项断言里的 gt911-probe 挂了，咱们看日志怎么报的：

```text
Goodix-TS 1-005d: error -EBUSY: Failed to get irq GPIO
```

-EBUSY，忙。触摸驱动的中断脚要不到。咱们顺着 GPIO1_IO09 这根脚查，发现它有两个主人在抢：EVK 参考板的 `imx6ul-14x14-evk.dtsi` 里，SD 卡电源调节器 reg_sd1_vmmc 用一根 GPIO 做使能控制，NXP 的设计里这根脚是 GPIO1_IO09：

```dts
reg_sd1_vmmc: regulator-sd1-vmmc {
	compatible = "regulator-fixed";
	regulator-name = "VSD_3V3";
	regulator-min-microvolt = <3300000>;
	regulator-max-microvolt = <3300000>;
	gpio = <&gpio1 9 GPIO_ACTIVE_HIGH>;
	enable-active-high;
};
```

而咱们的 AES 板上，GPIO1_IO09 接的是 GT9147 的触摸中断，板级 dtsi 里 gt9147 节点的 `irq-gpios = <&gpio1 9 GPIO_ACTIVE_HIGH>` 写的就是它。谁先 probe 谁先把脚申请走，后到的拿 -EBUSY。这次从零内核里触摸驱动 probe 得早，输给了 SD 电源调节器；您要是构建顺序略有不同，也可能是触摸先到、SD 卡初始化失败。同一根脚，两种病。

咱们的解法是承认这块板与参考板的接线差异，把电源调节器的使能控制拿掉：AES 板的 SD 卡电源不受 GPIO1_IO09 控制，只留电源描述：

```dts
	/* AES 板的 SD 卡电源不受 GPIO1_IO09 控制：这个脚是 GT9147 的触摸中断，
	   evk 参考板的使能写法不能照搬，只留电源描述 */
	reg_sd1_vmmc: regulator-sd1-vmmc {
		compatible = "regulator-fixed";
		regulator-name = "VSD_3V3";
		regulator-min-microvolt = <3300000>;
		regulator-max-microvolt = <3300000>;
	};
```

咱们把 `gpio` 与 `enable-active-high` 两行删掉，重编 dtb，GT911 当场认出 ID 911（下一篇验收节的表格里有它）。这段战史和前面 0x5d 那段凑成一对：一个是软件配置的双轨分歧，一个是硬件接线的参考板惯性，咱们共同的教训都是：参考板是起点不是终点，每一根脚的归属都要过一遍自己的原理图。

## 亲手造出这对文件，并注册给构建系统

讲完写法，落到操作。入口文件 imx6ull-aes.dts 很短，全文如下，您可以整段抄进 arch/arm/boot/dts/nxp/imx/：

```dts
// SPDX-License-Identifier: (GPL-2.0 OR MIT)
//
// Copyright (C) 2016 Freescale Semiconductor, Inc.

/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

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

咱们对着 EVK 的入口文件看，改动就三处：model 换成板子的名字；时钟树上比 EVK 多配了一路 PLL4_AUDIO_DIV 到 786432000Hz（24.576MHz 的整数倍，WM8960 的音频时钟从它来）；usdhc2 摘了 evk-emmc 变体的 8bit eMMC 配置。compatible 保留了 fsl,imx6ull-14x14-evk，mach 层靠它认机器，先沿用。

真正的工作量在 dtsi：从 imx6ul-14x14-evk.dtsi 起步，把上面盘点表里每一行落成节点。本章五个代表节点就是这份作业里最难的五道题；三个 GT/SD/codec 相关的战史点记得同步改；其余节点（QSPI、USB、LED、蜂鸣器、按键）照盘点表同法炮制。整套文件做完，下一篇验收的 15 项断言就是判卷标准；做卡了想对答案，随书仓库 driver/device_tree/alpha-board/linux/ 下的 imx6ull-aes.dts 与 imx6ull-aes.dtsi 就是成品原件，与您完成后的文件应逐字一致。

最后一步是注册：内核构建系统不认识 imx6ull-aes.dtb 这个名字，咱们要在 arch/arm/boot/dts/nxp/imx/Makefile 的 dtb 列表里加一行：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
/usr/bin/grep -n 'imx6ull-aes\|14x14-evk' arch/arm/boot/dts/nxp/imx/Makefile
```

```text
356:	imx6ul-14x14-evk.dtb \
380:	imx6ull-14x14-evk.dtb \
381:	imx6ull-aes.dtb \
421:	imx6ulz-14x14-evk.dtb \
```

就在 imx6ull-14x14-evk.dtb 后面加一行 `imx6ull-aes.dtb \`。这行改动是对内核树本体的修改，记得 git add 提交进您自己的分支，从零移植的产出（两份 dts、一份 defconfig、一行 Makefile 注册）从此都是您树里的正式成员。

## 继续学习

- 上一篇：[内核配置：动手做出自己的 defconfig](./06_defconfig_customize.md)，配置怎么来
- 下一篇：[编译、外挂模块与 QEMU 首启验收](./08_dts_build_boot.md)，把这对文件编成产物并在 QEMU 里首启验收
- 跨卷深读：[DRM 显示系统移植](./09_display_drm.md)，显示子系统深读，把本章 lcdif 那条链拆到驱动层
