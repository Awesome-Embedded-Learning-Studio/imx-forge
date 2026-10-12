---
title: 设备树：从参考板改出 AES 板，编译并首启
---

# 设备树：从参考板改出 AES 板，编译并首启

> 本篇解决一件事：手里有一棵主线内核和一块正点原子的 AES 板，怎么让内核认识板上的每一颗芯片。咱们从内核树自带的参考板出发，在您自己的树里亲手造出板级设备树文件对，编出 zImage 与 dtb，把第一颗外挂模块也编出来，最后在 QEMU 里首启，闯一遍 15 项断言验收。上一篇 [内核配置：一份 defconfig 的由来](05_defconfig.md) 备好了配置，本篇补上硬件描述这一半，从零移植就此收官；下一篇 [DRM 显示系统移植](07_display_drm.md) 钻进显示子系统。

::: tip 前置知识·环境
- 前置章：[内核配置：一份 defconfig 的由来](05_defconfig.md)、[取源码：从 stable 树拉下 v7.2.9](03_source_fetch.md)、[从零开始搭建主线内核编译环境](02_env_setup.md)、[BSP vs 主线对比](04_bsp_vs_mainline.md)
- 源码树 ~/experiments/linux-mainline（v7.2.9），构建目录 ~/experiments/linux-build（两目录制见 05 篇）
- QEMU 起机需要一份 rootfs 镜像与 qemu-system-arm：环境篇已备好 rootfs（本篇沿用），qemu-system-arm 用发行版包即可
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

咱们把编址规则看明白：两颗 PHY 都挂在 fec2 的 mdio 总线（管理总线）上，`reg` 是它们在这条总线上的地址，2 和 1，接线决定的，原理图说了算。`ethphy0/ethphy1` 两个标签分别被 `fec1` 与 `fec2` 的 `phy-handle` 引用，控制器靠它认领自己那颗 PHY。`compatible = "ethernet-phy-id0022.1560"` 直接写硬件 ID（0x0022 是 Micrel 厂商号，0x1560 是 KSZ8081 型号），比让内核读寄存器自识别更早定驱动。`phy-mode = "rmii"` 声明与 PHY 的数据接口是两线制 RMII。这颗 PHY 还给咱们留了一个关于 MAC 地址的坑，放到验收一节说。

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

GT9147 这段战史更微妙，您盯着 dts 里那个 0x5d 看半天也不会觉得它有问题。板级 dts 把 GT9147 写在 I2C2 的 0x5d，而实际的板子上实测这颗触摸在 0x14。0x5d 不是笔误：QEMU 的 gt911 模型把地址硬编码在 0x5d，本篇验收断言里的 gt911-probe 依赖它；实际的板子那侧的验证走驱动篇触摸章自己的板级 dts，写 0x14。同一颗芯片、两套环境、两个地址，这个分歧记录在本篇配套的说明文件里，修复排在 QEMU 的 gt911 模型支持改地址之后。

教训值得您带走：一套配置同时伺候模拟器和实际的板子时，任何分歧都必须白纸黑字写下来，写在哪、为什么、打算什么时候了结。不写下来，半年后没人记得 0x5d 是故意的，看起来就像 bug，然后有人在实际的板子上调三天触摸没反应。本篇验收节您会看到 `Goodix-TS 1-005d` 的日志，那就是 QEMU 侧的 0x5d 在说话。

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

咱们把 `gpio` 与 `enable-active-high` 两行删掉，重编 dtb，GT911 当场认出 ID 911（验收节的表格里有它）。这段战史和前面 0x5d 那段凑成一对：一个是软件配置的双轨分歧，一个是硬件接线的参考板惯性，咱们共同的教训都是：参考板是起点不是终点，每一根脚的归属都要过一遍自己的原理图。

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

真正的工作量在 dtsi：从 imx6ul-14x14-evk.dtsi 起步，把上面盘点表里每一行落成节点。本章五个代表节点就是这份作业里最难的五道题；三个 GT/SD/codec 相关的战史点记得同步改；其余节点（QSPI、USB、LED、蜂鸣器、按键）照盘点表同法炮制。整套文件做完，本篇验收的 15 项断言就是判卷标准；做卡了想对答案，随书仓库 driver/device_tree/alpha-board/linux/ 下的 imx6ull-aes.dts 与 imx6ull-aes.dtsi 就是成品原件，与您完成后的文件应逐字一致。

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

## 编译：zImage 与 dtb 两个产物

编译还是 05 篇那条 O= 命令，多一个 dtb 目标。这里有个新坑先踩给您看：dtb 目标得写子目录限定的全名，直接写文件名会扑空：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- imx6ull-aes.dtb
```

```text
make[3]: *** No rule to make target 'arch/arm/boot/dts/imx6ull-aes.dtb'.  Stop.
```

kbuild 把裸文件名解析到了旧目录 arch/arm/boot/dts/ 下（上游重组后真身在 nxp/imx/ 子目录），所以报 No rule。咱们写上子目录限定就对了：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j16 zImage nxp/imx/imx6ull-aes.dtb
```

```text
  LD      arch/arm/boot/compressed/vmlinux
  OBJCOPY arch/arm/boot/zImage
  Kernel: arch/arm/boot/zImage is ready
```

两个产物落在构建目录里，数一下个头：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
ls -l ~/experiments/linux-build/arch/arm/boot/zImage \
      ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
```

```text
-rw-r--r-- 1 charliechen charliechen   35594 Oct 12 08:41 /home/charliechen/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb
-rwxr-xr-x 1 charliechen charliechen 10369960 Oct 12 08:44 /home/charliechen/experiments/linux-build/arch/arm/boot/zImage
```

zImage 约 10.4MB（未做 05 篇第七节的裁剪），dtb 三万五字节。编出来的 dtb 值得随手反编译看一眼开头，model 和 chosen 直接告诉咱们内核将以什么身份、在哪个串口说话：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
~/experiments/linux-build/scripts/dtc/dtc -I dtb -O dts \
    ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb | sed -n '1,12p'
```

```text
/dts-v1/;

/ {
	#address-cells = <0x01>;
	#size-cells = <0x01>;
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

	chosen {
		stdout-path = "/soc/bus@2000000/spba-bus@2000000/serial@2020000";
	};
```

后面截断。咱们看得出来，源码里的 label 在产物里都换成了数字 phandle（比如触摸节点的 `pinctrl-0 = <0x0d 0x34>`），反编译产物读起来没有源码亲切，但它是内核真正吃到嘴的东西，核对死活就看它。

## 模块首编：给驱动篇铺的路

从零内核不只编镜像，驱动篇的教程模块（icm20608 六轴 IMU）也要对着这棵树编。外挂模块在 v7.2.9 上有三道前置，少一道都编不出来，咱们按真实的报错顺序走一遍。

第一道：构建目录里得有 scripts/module.lds。它是链接 .ko 时的地基，`make zImage` 不产它，咱们得显式跑一次 modules_prepare：

```bash
# 主机 ~/experiments/linux-mainline(源码树顶层)
make O=/home/charliechen/experiments/linux-build ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- modules_prepare
```

```text
  LDS     scripts/module.lds
```

缺它长什么样？笔者在补这一步之前硬闯过，modpost 之后的最后链接阶段报：

```text
make[3]: *** No rule to make target '21_tutorial_icm20608_spi_driver.ko', needed by '__modfinal'.  Stop.
```

这条报错相当误导：它说 .ko 没有规则可编，但您明明什么都没改坏，真相是 %.ko 这条链接规则把 module.lds 列为前置件，地基缺席，整条规则作废，报错却记在 .ko 头上。看到 No rule to make target 'xxx.ko'，先查 module.lds 在不在。

第二道：符号表。模块链接时要对照内核导出的符号地址，这表在构建目录的 vmlinux.symvers 里；而外挂模块构建流程读的是老名字 Module.symvers。kbuild 在这次改版里改了名、没留兼容，咱们自己补一个软链：

```bash
# 主机 ~/experiments/linux-build(构建目录)
ln -s vmlinux.symvers Module.symvers
ls -l vmlinux.symvers Module.symvers
```

```text
lrwxrwxrwx 1 charliechen charliechen     15 Oct 12 08:44 Module.symvers -> vmlinux.symvers
-rw-r--r-- 1 charliechen charliechen 786789 Oct 12 08:43 vmlinux.symvers
```

第三道：调用姿势。外挂模块必须用 O= 指向构建目录来编，这正是 05 篇立下两目录制的回报：源码树从头到尾没被原地构建污染过，O= 通道畅通。假想一下反例：您要是前几篇一直在源码树里原地编，这里再开 O=，kbuild 会直接拒绝，报 The source tree is not clean。

三道前置齐了，咱们编模块（教程模块源码取自驱动篇 SPI 一章，放任意目录都行）：

```bash
# 主机 模块源码目录
make -C /home/charliechen/experiments/linux-mainline \
    O=/home/charliechen/experiments/linux-build \
    ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- \
    M=$PWD modules
```

```text
  LD [M]  21_tutorial_icm20608_spi_driver.o
  MODPOST Module.symvers
  CC [M]  21_tutorial_icm20608_spi_driver.mod.o
  CC [M]  .module-common.o
  LD [M]  21_tutorial_icm20608_spi_driver.ko
```

11960 字节的 .ko 出炉。两个配套的坑一并交代，都是笔者实测撞过的：其一，模块与内核必须同源同 config，拿旧树的 .ko 往新内核上 insmod，内核报 `.gnu.linkonce.this_module section size must match the kernel's built struct module size`（config 不同导致结构体尺寸对不上）或 `disagrees about version of symbol module_layout`（版本对不上），一律回炉重编；其二，模块目录里若有上次的旧 .o，kbuild 会跳过重编直接复用，坑就从这里来：换内核重编模块前，把模块目录里的 .o、.cmd、.ko 清干净。

## QEMU 首启：15 项断言验收

镜像、dtb、模块三样齐了，咱们起机。QEMU 用 mcimx6ul-evk 机型直启内核（不经过 U-Boot），一条命令：

```bash
# 主机 任意目录
qemu-system-arm \
    -machine mcimx6ul-evk -m 512M \
    -kernel ~/experiments/linux-build/arch/arm/boot/zImage \
    -dtb ~/experiments/linux-build/arch/arm/boot/dts/nxp/imx/imx6ull-aes.dtb \
    -append "console=ttymxc0,115200 root=/dev/mmcblk1 rootwait rw" \
    -drive file=<rootfs 镜像>,if=sd,index=1,format=raw \
    -nic user \
    -nographic
```

rootfs 镜像用环境篇备好的那份；模块要 insmod 的话，您先用 debugfs 把 .ko 塞进镜像的 /root/。串口就是当前终端，Ctrl-A X 退出。

起机之前有一层等价性纪律值得咱们单说。QEMU 加载的就是实际的板子那棵 dtb：唯一的例外是两颗网卡的 `local-mac-address`。为什么 MAC 必须补？咱们把内核给网口找 MAC 地址的顺序说全。内核先看设备树里的 `mac-address`/`local-mac-address` 属性；都没有，再去查 ocotp 的 MAC fuse cell。i.MX6ULL 的 MAC fuse 出厂没烧写，fuse 空着、读回的值无效，内核再落到 FEC MAC 寄存器里 bootloader 写过的值。bootloader 也没写过的话，最后才是随机 MAC，dmesg 会打印 Using random MAC address。QEMU 的卡点在第二步：`of_get_mac_address()` 查 ocotp 的 nvmem cell 落空，两颗 FEC 一起卡在 deferred probe 里起不来。实际的板子上这个缺由 U-Boot 拿环境变量里的 ethaddr 在开机 fixup 时补进 dtb；QEMU 没有 U-Boot，咱们在起机前用 fdtput 往 dtb 副本里补同样的两个属性（FEC1 写 00:11:22:33:44:01，FEC2 写 00:11:22:33:44:02），改动打在编译产物上，恰好就是 U-Boot 动手的位置，dts/dtsi 源文件零改动，所以 QEMU 里验证过的结论对实际的板子同样成立。

15 项断言的完整验收是仓库的 e2e-test.sh 采的（它认 PROJECT_ROOT 环境变量，指向您自己的产物目录即可复用；本篇表格即笔者对这棵从零树跑出的原始记录）：

| 断言 | 判定输出 | 实测 | 验证了什么 |
|---|---|---|---|
| rtc-walk | RTCDELTA | 2 | RTC 注册为 rtc0，系统时钟走时正常 |
| net-dhcp-ping | NETRC | 0 | eth1 链路 Up，DHCP 拿到地址并 ping 通 10.0.2.2 |
| can0 | CAN0 | yes | flexcan1 注册出 can0 接口 |
| pwm-backlight | PWM | yes | pwmchip0 在位 |
| pwm-backlight | BL | yes | 背光设备在位 |
| display-fb | FB | yes | fb0 帧缓冲设备在位 |
| display-fb | MXSFB | yes | dmesg 有 Initialized mxsfb |
| usb-bus | USBN | 9 | 两条 ci_hdrc USB 总线起来 |
| sd-card | MMC | yes | QEMU 把 rootfs 卡挂到 USDHC2（if=sd,index=1）注册为 mmcblk1 并作根挂载；板上 usdhc1 SD 槽在 QEMU 中无卡，cd-gpios 插拔路径未被本次断言覆盖 |
| ap3216c-als | ALS | 0x0126 | i2c1 0x1e 光照寄存器读数有效 |
| icm20608-probe | ICM | yes | 模块 insmod 成功，SPI 驱动认出 ICM20608 |
| gt911-probe | GT911 | yes | Goodix-TS 报出 ID 911 |
| wm8960-codec | WM8960 | 0x00 | i2c1 0x1a 有应答（控制面寄存器模型，裸读有应答） |
| gpio-inject | GPIOFLIP | yes | 注入电平后 GPIO1_PSR 位 18 翻转 |
| deferred-list | DEFER_EXTRA | 0 | 除已知项外无设备卡在 deferred probe |

15 项全过。这份成绩单的分量在 icm20608-probe 那一行：它是唯一一项考验"模块与内核同源"的断言，本篇模块节编出的 .ko 塞进 rootfs 后 insmod 干净落地。从零内核加自编驱动，整条链都是您树里的产物。

咱们挑三条细看。rtc-walk：日志里 `snvs_rtc 20cc000.snvs:snvs-rtc-lp: registered as rtc0`，随后脚本取时间戳、睡 2 秒、再取，差值恰好 2。它验证的是一整条链：dts 里 snvs 节点活着、驱动 probe 成功、内核拿它当了时钟源、时间真的在走。时间类断言的好处是没法造假：时钟不走，差值就是 0。

wm8960-codec：`i2cget -y 0 0x1a 0x19` 读回了 0x00，说明 i2c1 总线上 0x1a 有器件应答，总线与地址都对。另一面也得说全：日志里同时有 `wm8960 0-001a: Not wm8960, wm8960 reg can not read by i2c`，内核驱动 probe 失败（-22）。翻脸的机制值得交代：驱动探测时用一次裸 i2c 读来认芯片，真 wm8960 恰恰对这种裸读不应答，QEMU 的控制面寄存器模型却应答了，驱动据此打印 Not wm8960 并返回 -EINVAL。所以这条断言验证的是咱们 dts 里 `wm8960@1a` 的挂载位置与地址，音频链路整体要在实际的板子上验。

gt911-probe 这条咱们细看：`Goodix-TS 1-005d: ID 911, version: 0020` 加一条 input 设备注册日志。这验证的就不只是地址了：驱动绑定成功，意味着中断 GPIO（GPIO1_IO09）、复位 GPIO（GPIO1_IO05）、pinctrl 组全都配对了——还记得战史三吗？这根中断脚差点被 SD 电源调节器的参考板写法占走，现在是触摸的。日志里 `goodix_911_cfg.bin` 加载失败（-2）是固件文件缺失，驱动带着默认配置继续跑，不致命。

## 在实际的板子上电

::: warning 未实测标注
在实际的板子上电（U-Boot 引导、tftp/netboot 拉 zImage 与 imx6ull-aes.dtb，或烧写 SD/eMMC）咱们在本环境没有硬件可跑：QEMU 的 mcimx6ul-evk 是直启内核，不经过 U-Boot 链路。操作以您所用 U-Boot 的 bootz 参数为准，串口输出以实际板子为准。
:::

在实际的板子上您要注意引导参数里的 dtb 必须是本文这份 `imx6ull-aes.dtb`，别拿成内核树里其它板子的。还有触摸地址：QEMU 侧写 0x5d，实际的板子上实测 0x14（战史二），实际的板子验证触摸按驱动篇触摸章的板级 dts 来。

## 坑速查

本篇的坑都散在正文里了，咱们收个尾，一张表备查：

| 现象 | 根因 | 解法 |
|---|---|---|
| make 报 No rule to make target 'arch/arm/boot/dts/imx6ull-aes.dtb' | dtb 目标没写子目录限定，kbuild 去旧目录找了 | 目标写成 nxp/imx/imx6ull-aes.dtb |
| dtc 报引用了不存在的节点或 label | `&xxx` 拼写与 SoC dtsi 里的 label 对不上 | 在 `imx6ul.dtsi`（必要时连同 `imx6ull.dtsi`）里 grep 该 label 核对拼写 |
| 触摸或其它 GPIO 器件 probe 报 -EBUSY | 一根 GPIO 两个主人（参考板的电源使能脚与本板中断脚撞车） | 对原理图裁决归属，删掉输家的 gpio 声明（战史三） |
| 模块编到 modpost 后报 No rule to make target 'xxx.ko', needed by '__modfinal' | 构建目录缺 scripts/module.lds，%.ko 链接规则作废 | `make O=... modules_prepare` 后重编 |
| 模块编过但链接时报符号未定义 | 构建目录缺 Module.symvers 符号表 | `ln -s vmlinux.symvers Module.symvers` |
| insmod 报 disagrees about version of symbol module_layout，或 struct module section size 不匹配 | 模块与内核不是同一次配置构建的产物 | 同一棵 O= 树、同一份 .config 重编模块，先清掉模块目录旧产物 |
| 网口 MAC 不确定，每次起机可能不同（dmesg 报 Using random MAC address，或探测早期短暂 deferred） | MAC fuse 没烧写，DT 里又没有 `local-mac-address`，内核查 ocotp 落空 | 引导固件补 MAC：U-Boot 配 ethaddr，QEMU 起机前 fdtput 补 |
| i2c 子设备 probe 报 -6 ENXIO | `reg` 地址与实际器件不符 | `i2cdetect` 扫总线确认地址再写 `reg` |
| spi 子设备乱码或不响应 | `spi-max-frequency` 超器件规格，或 `reg` 片选编号与 `cs-gpios` 对不上 | 对器件手册核频率；片选编号从 0 数 |
| 屏幕花屏或不亮但 fb0 在 | `panel-timing` 时序与屏不符 | 对屏幕手册逐项核时序，像素时钟错最常见 |

## 继续学习

- 上一篇：[内核配置：一份 defconfig 的由来](05_defconfig.md)，内核配置怎么来
- 下一篇：[DRM 显示系统移植](07_display_drm.md)，显示子系统深读，把本篇 lcdif 那条链拆到驱动层
- 跨卷：[主线内核调试技巧](10_debug_tricks.md) 与 [常见问题与解决方案](11_common_issues.md)，起机不顺时按图索骥
