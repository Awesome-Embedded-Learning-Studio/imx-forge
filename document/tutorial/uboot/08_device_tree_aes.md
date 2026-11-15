---
title: 设备树：imx6ull-aes 从参考板改到了咱们的板子
current_status:
  title: 正在打磨
  detail: 本篇成文不久，表述与示例还在逐站校对，内容可能随时调整
  variant: polishing

---

# 设备树：imx6ull-aes 从参考板改到了咱们的板子

> 07 章把 imx6ull-aes.dts 与 imx6ull-aes.dtsi 这两个名字登记进了构建系统，编译验收一过就收了工。本篇咱们把这两份文件摊开逐节点对，讲清 AES 的设备树从哪来、每一处为什么这么写、哪些是从参考板原样保留的、哪些是按 AES 的硬件改的。旧稿那篇通用设备树教学在本篇退役，通用语法压成第一节的最小背景，深读归驱动卷的设备树系列，交给内核的那份归内核卷。下一篇 09 章回到 DDR 初始化与 imx 镜像头。

07 章收尾留了个活扣：dtsi 里 398 行的 usdhc2 配的是 4 位引脚组，顶层 dts 却写着 `bus-width = <8>`。同一块 eMMC，位宽到底听谁的？咱们从这个问题开讲，把两份文件的接力规则与关键节点的出身讲清楚，结尾请反编译出来的 dtb 当裁判。

## 一、设备树在 U-Boot 里管什么

背景压到最短，三句话讲完。dts 是人读的文本，经 dtc 编译成 dtb 二进制。U-Boot 用 `CONFIG_OF_CONTROL` 这个开关决定要不要读它，开关合上，驱动模型（DM）就按节点里的 compatible 字符串认外设、绑驱动——串口从哪出、eMMC 挂在哪、网口怎么接线，全以这份 dtb 为准，那轮构建留下的 `.config` 里 `CONFIG_OF_CONTROL=y` 可查。还有一条边界咱们得划清：U-Boot 自己用的 DT 与传给内核的 DT 是两份独立文件，各自编译、各自随各自的镜像走，本篇只管 U-Boot 这份，内核那份归内核卷，语法层的系统教学是驱动卷设备树系列的主场，本篇不重复。

## 二、从参考板到 AES：补丁新增了两个文件

补丁动到 13 个文件，dts 段只新增两个。咱们在源码树里 ls 过：

```bash
# 主机 ~/imx-forge
ls third_party/uboot-mainline/arch/arm/dts/ | grep aes
```

```text
imx6ull-aes.dts
imx6ull-aes.dtsi
```

暂存区里的规模也核过一遍：

```bash
# 主机 ~/imx-forge
git -C third_party/uboot-mainline diff --cached --stat -- arch/arm/dts | tail -4
```

```text
 arch/arm/dts/imx6ull-aes.dts  |  44 +++
 arch/arm/dts/imx6ull-aes.dtsi | 729 ++++++++++++++++++++++++++++++++++++++++++
 2 files changed, 773 insertions(+)
```

stat 说 dtsi 是 729 行，那是暂存区快照的数字。工作区里的终稿 735 行，补丁里也是 735 行，`git status` 里这个文件挂着 AM 状态，先入了暂存区、后来又改过一轮。差出来的那轮改动不止两类：网口复位引脚组的补挂与 SNVS 引脚组的搬家之外，sai2 的 pinctrl-0 还补挂了终稿新增的耳机检测组 pinctrl_hp_det（检测脚从 pinctrl_sai2 组里挪出来单独成组），reg_peri_3v3 还补了一行 regulator-boot-on。SNVS 搬家那层第三节展开，咱们先把差数记全，免得后面对不上号。

### dts 与 dtsi 的分工

44 行的 dts 是板级入口，骨架咱们引来：

```dts
/dts-v1/;

#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"
#include "imx6ull-14x14-evk-u-boot.dtsi"

/ {
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
};
```

三个 include 各管一层。`imx6ull.dtsi` 是 SoC 基线，开头就把 `imx6ul.dtsi` 整个包进来，CPU、时钟控制器、两块 usdhc、两块 FEC 这些片内外设的全集都住在 `imx6ul.dtsi` 里，usdhc 和 fec 这些外设的 status 默认是 disabled，等板级层来点亮（CPU 与时钟控制器节点没有 status 属性，在基线里本来就是启用的）。`imx6ull.dtsi` 本体只有 95 行，只补 6ULL 特有的部分，`iomuxc_snvs` 这个节点就在 `imx6ull.dtsi` 的 78 行。`imx6ull-aes.dtsi` 是板级主体，735 行里装着 chosen、memory、稳压器、双网口、LCD 时序与全部引脚组，是本篇的正主。第三份 `imx6ull-14x14-evk-u-boot.dtsi` 全文 12 行，只有两个节点的标记，咱们原样引来：

```dts
&pinctrl_uart1 {
	bootph-all;
};

&rngb {
	bootph-all;
};
```

bootph-all 是 U-Boot 自家的标记属性，咱们按文档的说法理解它：声明这节点在所有启动阶段都得在册。它最典型的用场在 scripts/Makefile.xpl 里看得到，578 行的 `dt-$(SPL_NAME).dtb` 那条规则用 fdtgrep 从全量 dtb 里裁出 SPL 用的一份（602 行 `$(call if_changed,fdtgrep)`），裁留的依据在 scripts/Makefile.lib 的 668 行起，就是这类标记。串口引脚组不打标记，就进不了被裁出的那份名单。rngb 是片内随机数发生器，同批入册。

dts 剩下的四段都是覆盖，咱们挨个看：`&clks` 补上两路时钟频率，PLL3_PFD2 定到 320000000，音频那路 PLL4_AUDIO_DIV 定到 786432000，`&csi` 与 `&ov5640` 把 SoC 层默认关着的摄像头链路点亮，`&usdhc2` 把 eMMC 的 8 位配置盖上去，这段留给第三节细看。dts 写差异、dtsi 写主体，这个分层是从蓝本继承的：EVK 的入口 `imx6ull-14x14-evk.dts` 只有 18 行，板级主体同样住在 `imx6ul-14x14-evk.dtsi` 里。

### 与蓝本的同与不同

同的部分咱们拿 diff 对过：chosen 指向 uart1、memory 从 0x80000000 起 512 MiB、usdhc1 的三态引脚加卡检测，这几段与蓝本逐字同款。改的地方都有硬件理由。蓝本的 usdhc2 是 SD 式接法，带着 `broken-cd` 与 `no-1-8-v`，AES 换成了 eMMC 的 `non-removable`。蓝本带 backlight 加 panel（innolux,at043tn24 的 4.3 寸屏）那套主线式 LCD 节点，AES 没要，改用 lcdif 节点下的 display0 时序表按 1024x600、51.2 MHz 的屏配。蓝本的摄像头节点叫 camera@3c，AES 保留供应商风格的 ov5640@3c 并在顶层使能。

usdhc2 这处改动的出处，dts 里留着作者注释，咱们原样引来：

```dts
/*
	usdhc2 is assigned from arch/arm/dts/imx6ull-14x14-evk-emmc.dts
	which we simplified the include hieracy
*/
```

注释里那个 imx6ull-14x14-evk-emmc.dts 在主线 v2026.10 里并不存在，咱们把 dts 目录 ls 了一遍，i.MX6ULL 带 emmc 字样的板卡只有 colibri 与 phytec 两家。它是 NXP 下游树里的文件——那边把 SD 板与 eMMC 板拆成两个 dts，咱们把简化后的 eMMC 配置直接叠进顶层覆盖。

还有一处位置变化值得单独交代。笔者把旧稿翻出来对过，旧稿说 UART1_TX_DATA 这类引脚宏定义在 imx6ul-pinfunc.h 里，没提目录。旧稿指的 imx6ul-pinfunc.h 在这棵 v2026.10 的 arch/arm/dts/ 下已经不在了，目录里剩的 imxrt1020-pinfunc.h 与 mt8189-pinfunc.h 是别的芯片家族的表，i.MX 的这份搬到了 dts/upstream/src/arm/nxp/imx/ 下。咱们 grep 宏的定义，命中的路径在 upstream 一侧：

```bash
# 主机 ~/imx-forge
grep -rn "define MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX" third_party/uboot-mainline | head -2
```

```text
third_party/uboot-mainline/dts/upstream/src/arm/nxp/imx/imx6ul-pinfunc.h:164:#define MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX		0x0084 0x0310 0x0000 0 0
```

宏本体搬进了上游设备树的目录，预处理时 scripts/Makefile.lib 里的 upstream_dtsi_include 把这些路径加进 -I，include 才解析得到。照旧稿去 arch/arm/dts 下找头文件要扑空，这层是旧稿没交代的，咱们把它补在这里。

## 三、关键节点逐个对

### chosen 与串口

控制台从哪来，dtsi 开头几行就有答案：

```dts
chosen {
	stdout-path = &uart1;
};

memory@80000000 {
	device_type = "memory";
	reg = <0x80000000 0x20000000>;
};
```

chosen 是给启动程序看的约定节点，stdout-path 指到 uart1，U-Boot 的控制台就落在它身上。memory 声明 512 MiB DDR 从 0x80000000 起，与 07 章头文件里 PHYS_SDRAM 那套宏互为印证。uart1 节点在 dtsi 的 349 行，咱们看它的引脚组，UART1_TX_DATA 与 UART1_RX_DATA 两个 pad 在这里配成 DCE 收发，电气值 0x1b0b1。别名出自 SoC 基线，imx6ul.dtsi 的 aliases 段写着 serial0 = &uart1，反编译后的 dtb 里 serial0 对着 `serial@2020000` 这个路径。eMMC 的编号也从同一张表来，mmc0 对 usdhc1、mmc1 对 usdhc2，07 章环境变量里 emmc_dev=1 的那个 1 就在这里对上号。

### usdhc 两兄弟：SD 卡槽与 eMMC

dtsi 基线里两个控制器一前一后，咱们把两段都引来：

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

&usdhc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_usdhc2>;
	non-removable;
	keep-power-in-suspend;
	wakeup-source;
	status = "okay";
};
```

usdhc1 是 SD 卡槽，卡检测走 GPIO1_IO19，供电由 reg_sd1_vmmc 这个固定稳压器管，三组引脚对应三个频段。usdhc2 是 eMMC，`non-removable` 声明芯片焊在板上，驱动省掉热插拔逻辑。注意它没写 bus-width，没写就是继承：SoC 基线 imx6ul.dtsi 的 usdhc2 节点自带 `bus-width = <4>`（916 行），所以 dtsi 层按 4 位总线跑。8 位引脚组其实早已备好，咱们在 iomuxc 段 650 行起看得到，pinctrl_usdhc2_8bit 连同 100mhz、200mhz 两个变频组排在那里，只是这一层没人引用它们。

顶层 dts 把最后这一手接过来：

```dts
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

设备树后写的覆盖先写的，同名属性以 include 顺序靠后者为准，dts 排在 dtsi 之后，于是三态引脚换成 8 位组、bus-width 落定 8，non-removable 两层同值，合并后只有一份。咱们开头留的那个活扣，答案就是这句：dtsi 是 4 位基线，dts 是 8 位终态，听后写的。

位宽与引脚组这对搭档还得配套。bus-width 是控制器侧的行为约定，引脚组是物理复用的约定，两处必须指到同一个现实。手一滑只把 bus-width 写成 8、引脚组留在 4 位组，DATA4 到 DATA7 四根线没配到 usdhc 功能上，控制器按 8 位发数据，高 4 位读回来的是悬空电平，eMMC 枚举多半当场失败。反过来只换引脚组不写位宽，芯片按 4 位跑，8 位芯片一半的带宽白扔。合并效果咱们拿反编译的 dtb 验过，证据第五节一起贴。两兄弟放到一张表里对看：

| | usdhc1 | usdhc2 |
|---|---|---|
| 接的介质 | SD 卡槽 | eMMC 芯片 |
| 别名 | mmc0 | mmc1 |
| 位宽 | 4 位，SoC 基线保持 | 8 位，顶层覆盖落定 |
| 引脚组 | 三态 4 位组 | 基线 4 位组被顶层换成三态 8 位组 |
| 卡检测 | cd-gpios 走 GPIO1_IO19 | non-removable，无卡检测 |
| 供电 | vmmc-supply 接 reg_sd1_vmmc | 无独立供电属性 |

### fec 两块网口与 PHY

网口骨架咱们整段引来（dtsi 161 行起）：

```dts
&fec1 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_enet1 &pinctrl_enet1_reset>;
	phy-mode = "rmii";
	phy-handle = <&ethphy0>;
	phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
	phy-reset-duration = <200>;
	phy-reset-post-delay = <200>;
	phy-supply = <&reg_peri_3v3>;
	status = "okay";
};
```

fec2 写法同款，复位脚换 GPIO5_IO08，phy-handle 指向 ethphy1，它名下的 MDIO 总线咱们也引来：

```dts
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
```

两颗 PHY 的 compatible 都写着 ethernet-phy-id0022.1560，前半段是 Micrel 的厂商编号、后半段是型号编号，对上的是 KSZ8081，07 章板级 C 代码里 board_phy_config 补的那组寄存器伺候的就是它。两颗 PHY 挂同一条 MDIO 总线，靠 reg 地址 2 与 1 分开，咱们在 07 章 defconfig 里见过的那句 DM_MDIO 注释（两块 FEC 共用一条 MDIO，交接内核时总线生命周期交给 DM 管）说的就是这层。控制器节点本身在 SoC 基线里，compatible 写 fsl,imx6ul-fec，aliases 里 ethernet0 与 ethernet1 分别对应 fec1 与 fec2，phy-mode 选 rmii，比 MII 省一半引脚，是 i.MX6ULL 板卡的标准选择。

这一节的节点咱们修过一轮，暂存区快照留了证据：最初 fec1 的 pinctrl-0 只写 `<&pinctrl_enet1>`，复位引脚组 pinctrl_enet1_reset 定义了却无人引用，终稿才把两块 enet 的复位组补进 pinctrl-0。复位组为什么非补不可，下一小节接着讲。

### pinctrl 引脚组与 SNVS 的搬家

引脚组全 dtsi 一个模板，咱们拿 uart1 的做例子：

```dts
pinctrl_uart1: uart1grp {
	fsl,pins = <
		MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
		MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
	>;
};
```

每行六个数，前五个来自宏展开。第二节 grep 到的那行 define 原文是 `0x0084 0x0310 0x0000 0 0`，五个数依次是 mux 寄存器偏移、pad 配置寄存器偏移、daisy 输入偏移、复用模式、daisy 输入值，行尾的 0x1b0b1 是第六个，pad 电气配置。咱们拿反编译的 dtb 对过，usdhc 的引脚组在 dtb 里正是六数一行（0x178 0x404 0x670 0x01 0x02 0x17059 这样的序列），宏在预处理阶段已展开成纯数字。电气值随频段走，同一个 CLK 脚默认态 0x10069、100mhz 态 0x100b9、200mhz 态 0x100f9，逐级上调的是驱动强度与转换速率，数值照 i.MX6ULL 参考手册的 IOMUXC 表查。

组名的惯法是 `pinctrl_x: xgrp`，前半给节点引用当标号，后半是组名。挂哪间屋子有讲究，这里正是咱们翻过车的地方。6ULL 的引脚控制器有两处：主处 iomuxc 在 0x020e0000，另一处 iomuxc_snvs 在 0x02290000，节点定义在 imx6ull.dtsi 的 78 行：

```dts
iomuxc_snvs: iomuxc-snvs@2290000 {
	compatible = "fsl,imx6ull-iomuxc-snvs";
	reg = <0x02290000 0x4000>;
};
```

::: warning SNVS 域引脚组挂错控制器，编译不报错，寄存器写错地方
网口复位、耳机检测、外设电源使能这几根线都走 GPIO5 上 SNVS 域的 pad，6ULL 把这批 pad 挪进了 0x02290000 的独立控制器，宏名也换成 MX6ULL_PAD_SNVS 打头。事故的成因是照 6UL 的老写法把引脚组挂进主控制器 iomuxc、用 MX6UL_PAD_SNVS 打头的宏：两套宏在头文件里都存在（MX6UL 那套定义在 6UL 的表里，pad 配置偏移指向主控制器的 0x020E02B0 一带），预处理一声不吭，dtc 也照单收数，寄存器却写错了地方，引脚电气配不上，复位线不动，PHY 起不来。咱们暂存区里那版 729 行的 dtsi 就犯过这个毛病，sai2 的耳机检测、peri 电源使能、spi-4 那条总线的引脚组（pinctrl_spi4）全挂在主控制器名下，终稿全部搬进 `&iomuxc_snvs` 并换成 MX6ULL_ 前缀的宏，dtsi 702 行那行搬家注释写着 i.MX6ULL SNVS pads belong to the separate 0x02290000 controller。07 章 Kconfig 里 select IOMUX_LPSR 给的就是这批寄存器的访问支持。
:::

fec 那轮咱们补的正是同族问题：pinctrl_enet1_reset 与 pinctrl_enet2_reset 挂在 `&iomuxc_snvs` 里（MX6ULL_PAD_SNVS_TAMPER7 与 TAMPER8 两个 pad），引脚组不生效，PHY 复位线停在悬空状态，网口枚举不到 PHY 芯片，链条与上面那条同根。

其余节点咱们一笔带过，免得本篇失焦。dtsi 里还备着 wm8960 音频链路（i2c2 上的 codec 配 sai2）、can1 与 can2、qspi 上的 nor flash（micron,n25q256a，29 MHz）、tsc 电阻触摸、两路 USB、wdog1、1024x600 的 LCD 时序、i2c1 上的磁力计与加速度计，还有一条 spi-gpio 模拟出来的 spi-4 总线，挂一颗 74hc595 移位寄存器，摄像头的 powerdown 与 reset、CAN 电源的使能都从它借脚。这条总线的名字有三副：节点名就叫 spi-4，引脚组叫 pinctrl_spi4，aliases 里登记的别名却是 spi5，别名编号跟节点名不挂钩。这些按 AES 板的实际硬件取舍，wm8960 在驱动卷音频那章展开。

## 四、让构建系统认识它

登记动作 07 章已经做完，回收一句：configs/mx6ull_aes_emmc_defconfig 第 12 行写着 `CONFIG_DEFAULT_DEVICE_TREE="imx6ull-aes"`，设备树的户口就在这行上。惯例还会往 arch/arm/dts/Makefile 的 dtb 清单里补一行，官方板卡都这么登记。咱们按惯例去核，命令跑完一个字的输出都没有，grep 退出码 1，清单里确实没有这个名字，补丁也没带这行：

```bash
# 主机 ~/imx-forge
grep -n "imx6ull-aes" third_party/uboot-mainline/arch/arm/dts/Makefile
```

07 章当时把这归结为模式规则认文件名。这一节咱们把机制再往下翻一层，真正的接线在 scripts/Makefile.dts，头一行就把 `CONFIG_DEFAULT_DEVICE_TREE` 与 `CONFIG_OF_LIST` 拼进 dtb 清单，而 OF_LIST 的缺省值恰好取自 DEFAULT_DEVICE_TREE（dts/Kconfig 的 238 行写着 default DEFAULT_DEVICE_TREE）。imx6ull-aes.dtb 其实进了 dtb-y 清单，只是进得无声无息，不劳手写。那轮构建的日志里抓得到现场：

```bash
# 主机 ~/imx-forge
grep -n "imx6ull-aes" /tmp/uboot-ref-build.log | head -3
```

```text
1360:  DTC     arch/arm/dts/imx6ull-aes.dtb
```

U-Boot 怎么消费这份 DT，咱们一句带过：`CONFIG_OF_CONTROL=y` 加 `CONFIG_OF_SEPARATE=y` 的组合下（那轮 .config 可查），dtb 编出来随镜像走，上电后驱动模型照 compatible 绑驱动，chosen 的 stdout-path 指挥控制台，bootph-all 保住串口引脚组与 rngb 的全程在册。

## 五、验收：反编译看真容

源码对读完了，咱们把裁判请出来，dtb 反编译回文本：

```bash
# 主机 ~/imx-forge
dtc -I dtb -O dts /tmp/uboot-ref-aes/u-boot.dtb 2>/dev/null | grep -m4 "model\|compatible"
```

```text
	model = "Awesome Embedded Studio IMX6ULL (i.mx NXP)";
	compatible = "fsl,imx6ull-14x14-evk\0fsl,imx6ull";
			compatible = "arm,cortex-a7";
		compatible = "arm,armv7-timer";
```

dtb 是 11 月 14 日 14:01 那轮的产物，33096 字节，反编译用的 dtc 是咱们主机上的 1.7.0。头两行是根节点，第三、四行来自 SoC 基线里的 CPU 与定时器节点。model 是 AES 的名字，compatible 却还是 EVK 那一串——这里头没有矛盾，咱们一层层看：compatible 的值是字符串数组，反编译里用 \0 分隔。U-Boot 认板不认这串，认的是 Kconfig 与 defconfig（TARGET_MX6ULL_AES_EMMC）。驱动绑定发生在每个设备节点上，用的是 SoC 基线的 compatible。根节点这一串是板卡身份的描述性签名，保留 EVK 写法等于声明这块板与 EVK 同族。运行上没有影响。

第三节的合并结论咱们拿到这里过堂：反编译的 mmc@2194000 节点带着 `bus-width = <0x08>`、三态 pinctrl 与 non-removable，pinctrl-0 指向的 0x2e 号 phandle 正是 usdhc2grp_8bit。4 位的 usdhc2grp 在反编译里连 phandle 都没有，全树没有任何引用指向它。相邻的 mmc@2190000 保持 `bus-width = <0x04>`，SD 卡槽照旧 4 位。顶层覆盖真的生效，源码与产物两边对上了。

## 六、与内核设备树的关系

第一节划的边界咱们现在能补细节了。U-Boot 这份与传内核那份同名不同命，名字都叫 imx6ull-aes.dtb，出生地是两棵源码树。U-Boot 这份在 third_party/uboot-mainline/arch/arm/dts/ 里编出来，上一节验收过了。内核那份要等内核源码树编译，内容也不必相同，bootph-all 这类 U-Boot 自家标记只出现在 U-Boot 这份里。启动脚本写在补丁的 1767 行，值得单独过一眼：

```text
"loademmcfdt=ext4load mmc ${emmc_dev}:1 ${fdt_addr} /imx6ull-aes.dtb\0" \
```

这句咱们逐段看：它把 eMMC 第一分区根目录下的同名文件读进 fdt_addr，等着交给内核。什么时候递、内核怎么接，归内核卷，内核卷讲 dts 写法与编译启动的两章已经落成，交接动作随内核卷讲到交接时展开。

这一程咱们实测下来的三个数先摆在这儿：dts 44 行，dtsi 735 行，反编译过的 dtb 33096 字节。

## 继续学习

- [七步造出咱们的板卡](./07_board_porting.md)：登记两份设备树名字的那一篇，defconfig 与编译验收在那边。
- [DDR 初始化与 imx 镜像头](./09_ddr_imxheader.md)：下一篇，从设备树回到镜像头的 DDR 那条线。
- [设备树开篇](../driver/01_device_tree_base/01_device_tree_introduction.md)：语法深读的起点，驱动卷这个系列共五篇。
- [内核侧的 dts 写法](../kernel/07_dts_writing.md)：交给内核那份怎么写，内核卷已有落成的一章。
- [dts 的构建与启动](../kernel/08_dts_build_boot.md)：内核那份怎么编、怎么被消费，在那边展开。
