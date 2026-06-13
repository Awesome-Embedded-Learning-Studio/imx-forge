---
title: 网络驱动移植
---

# 网络驱动移植：从ping不通到tftp成功，那些让你抓狂的PHY时序问题

## 前言：网络调试的痛苦谁懂

孩子们，到网络了。

串口你插上就能用，eMMC你只要焊对了引脚基本就能读写，但网络不行。网络是个系统工程：MAC控制器要配对、PHY芯片要复位、时钟要同步、MDIO总线要通、PHY地址不能冲突、引脚复用要正确……任何一个环节出问题，结果就是一样的——ping不通。我是真遇到过从PHY层次搞错了，到桥接模式和NAT狠狠干了我一顿（不到啊，你这不在同一层网络我咋ping通你啊），到UBuntu的ufw投诉我很多莫名其妙的包来（哥啊，他们是我客人你咋把他们赶出去）的症状都是——孩子，ping不同。

摔桌子。

更糟糕的是，网络问题的症状往往很隐晦。有时候PHY能初始化但link up不起来，有时候link起来了但ping不通，有时候ping通了但tftp超时。这些问题的排查过程足以让一个工程师对"到底是我的板子有问题还是PHY芯片有问题"产生哲学思考。

但网络太重要了。没有网络，你就没法用tftp下载内核、没法用nfs挂载根文件系统，每次更新代码都要重新烧录eMMC，开发效率低到令人发指。所以不管网络调试有多痛苦，这关我们得过。

这篇文章会带你完整地走一遍i.MX6ULL的网络驱动移植过程。你会发现，所谓的"网络黑魔法"其实都有清晰的逻辑，只要你理解了MAC、PHY、MDIO、RMII这些概念之间的关系，网络调试就不再是无从下手的黑盒。

## FEC以太网控制器：i.MX6ULL的双网卡架构

i.MX6ULL有两个FEC（Fast Ethernet Controller）控制器，分别叫fec1和fec2。这两个控制器本质上是一样的，都是10/100Mbps以太网MAC，但在硬件设计上有一些差异需要注意。

第一个差异是ENET2的熔丝问题。i.MX6ULL的一些变体的ENET2功能可能被熔丝熔断，这意味着如果你的芯片恰好是这种变体，fec2就永远用不了。NXP的官方代码里有个`check_module_fused(MODULE_ENET2)`函数，就是用来检测这个的。我们的代码里也保留了这个检测，如果你发现fec2死活不工作，先确认一下你的芯片有没有这个熔丝问题。

第二个差异是时钟源的配置。i.MX6ULL的以太网控制器需要一个50MHz的参考时钟，这个时钟可以来自外部晶振，也可以从芯片内部的PLL通过Anatop系统时钟单元生成。我们的板子使用的是内部时钟生成方案，也就是后面会在setup_fec函数里配置的ENET_50MHZ时钟源。

第三个差异是MDIO总线的挂载方式。fec1和fec2共享一个MDIO总线，但PHY地址必须不同。如果你的两个PHY芯片地址一样，MDIO总线就会冲突，结果是两个PHY都无法正常通信。这个问题在板级设计阶段就要考虑清楚，硬件工程师通常会通过PHY芯片的PHYAD引脚来设置不同的地址。

理解这三个差异很重要，因为它们分别对应了我们在移植过程中要解决的三个问题：时钟配置、PHY地址配置、MDIO总线配置。

## PHY芯片选择：KSZ8081为什么这么受欢迎

PHY芯片是MAC和物理传输介质之间的桥梁，负责把MAC的数字信号转换成能在网线上传输的模拟信号。i.MX6ULL的FEC控制器需要外接一个PHY芯片才能工作，市面上常见的PHY芯片有LAN8720A、KSZ8081、KSZ8091等几种。

我们的板子用的是KSZ8081RNA，这是一颗Micrel（已经被Microchip收购）的PHY芯片。为什么选择它？首先它是RMII接口的，相比MII接口少用了一半的引脚，对于引脚紧张的板子很友好。其次它内部集成了50MHz的振荡器，可以省掉外部晶振。最后它的功耗很低，适合对功耗敏感的应用。

KSZ8081的PHY地址可以通过PHYAD引脚配置。当PHYAD引脚悬空时，默认地址是1；当PHYAD引脚接高电平时，地址是2；当PHYAD引脚接低电平时，地址是0。这个很重要，因为设备树里的`reg = <1>`或`reg = <2>`必须和硬件的实际配置一致，否则MDIO总线找不到PHY芯片。

我们板子的硬件设计是这样的：eth0的PHY地址是2，eth1的PHY地址是1。所以在设备树里你会看到`ethphy0: ethernet-phy@2`和`ethphy1: ethernet-phy@1`这样的配置。这个顺序听起来有点反直觉——为什么eth0用地址2而eth1用地址1？这完全是历史原因，板子设计成这样了，我们只能照着写。

KSZ8081还有几个重要的配置项需要注意。一个是LED模式，通过`micrel,led-mode = <1>`设置，值1表示LED模式1，具体的行为可以参考KSZ8081的数据手册。另一个是时钟源配置，通过`clocks = <&clks IMX6UL_CLK_ENET_REF>`和`clock-names = "rmii-ref"`来指定RMII参考时钟的来源。

## 设备树网络配置：一步步来

设备树是网络配置的核心，我们先看完整的fec1和fec2配置，然后逐项解释。

```
&fec1 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_enet1>;
	phy-mode = "rmii";
	phy-handle = <&ethphy0>;
	phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
	phy-reset-duration = <200>;
	phy-reset-post-delay = <200>;
	phy-supply = <&reg_peri_3v3>;
	status = "okay";
};

&fec2 {
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_enet2>;
	phy-mode = "rmii";
	phy-handle = <&ethphy1>;
	phy-reset-gpios = <&gpio5 8 GPIO_ACTIVE_LOW>;
	phy-reset-duration = <200>;
	phy-reset-post-delay = <200>;
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

`pinctrl-names`和`pinctrl-0`指定了引脚配置，这个我们后面会详细说。`phy-mode = "rmii"`表示使用RMII接口模式，相比MII模式少用了一半的引脚。如果你的PHY芯片是MII接口的，这里要改成"mii"。

`phy-handle`指向具体的PHY设备节点，fec1指向ethphy0，fec2指向ethphy1。这个引用关系很重要，驱动程序通过它找到对应的PHY配置。

`phy-reset-gpios`指定PHY复位GPIO，fec1用GPIO5_7，fec2用GPIO5_8。`GPIO_ACTIVE_LOW`表示低电平有效，也就是说拉低这个GPIO会复位PHY芯片。为什么是GPIO5_7和GPIO5_8？这是我们的硬件设计决定的，你的板子可能用不同的GPIO，要根据原理图确认。

`phy-reset-duration`指定复位信号保持时间，单位是毫秒。200ms是一个保守值，大多数PHY芯片的数据手册要求的复位时间都比这短，但长一点没关系。`phy-reset-post-delay`指定复位结束后的等待时间，也是200ms，给PHY足够的时间完成内部初始化。

`phy-supply`指定PHY的电源供给，这里是`reg_peri_3v3`，一个3.3V的外设电源。这个电源必须是稳定的，如果PHY供电不稳，网络会出现各种奇怪的问题。

MDIO子节点定义了两个PHY设备。`#address-cells = <1>`和`#size-cells = <0>`表示PHY设备用单个地址编码，没有size属性。`ethphy0`和`ethphy1`是节点名称，`@2`和`@1`是unit address，必须和`reg`属性的值一致。

`compatible = "ethernet-phy-id0022.1560"`是PHY的标识符，0022是Micrel的OUI，1560是KSZ8081的型号ID。U-Boot的PHY驱动通过这个ID匹配对应的驱动程序。如果你用LAN8720A，这里的ID要改成对应的值。

`reg`属性指定PHY地址，必须和硬件的PHYAD引脚配置一致。`micrel,led-mode = <1>`设置LED模式，`clocks`和`clock-names`指定RMII参考时钟的来源。注意fec2用的是`IMX6UL_CLK_ENET2_REF`，fec1用的是`IMX6UL_CLK_ENET_REF`，这是因为两个控制器的时钟源是独立的。

## MDIO总线：MAC和PHY之间的控制通道

MDIO（Management Data Input/Output）总线是MAC控制器用来读写PHY寄存器的接口。它只有两根线：MDC（时钟）和MDIO（数据），通过类似I2C的时序来访问PHY的寄存器空间。

i.MX6ULL的fec1和fec2共享一个MDIO总线，这意味着两个PHY芯片挂载在同一条MDIO总线上。MDIO总线的一个重要特性是每个PHY必须有唯一的地址，否则会产生总线冲突。

PHY地址通常是5位的，可以表示0到31之间的值。但在实际使用中，常用的地址是0、1、2这几个。KSZ8081的默认地址是1，可以通过PHYAD引脚配置成0或2。

我们的板子把eth0的PHY地址设为2，eth1的PHY地址设为1。为什么eth0不用地址0？这是历史遗留问题，板子设计的时候eth0的PHYAD引脚接了高电平，所以地址变成了2。如果你的板子设计不同，这里的配置也要相应调整。

PHY寄存器0和1是控制寄存器和状态寄存器，最常读的是寄存器1（Basic Status Register）。bit2表示link status，如果读到0x0004或0x0005之类的值，说明PHY已经link up。如果一直读不到这个bit，说明PHY没有和网线另一端建立连接，问题可能在PHY配置、网线、或者对端设备上。

## 时钟配置：50MHz从哪来

i.MX6ULL的以太网控制器需要一个50MHz的参考时钟，这个时钟的来源有两种选择：外部晶振或者内部PLL。我们的板子用的是内部PLL方案，具体是通过Anatop系统时钟单元的PLL3生成。

时钟配置的代码在setup_fec函数里：

```c
/*
 * Use 50M anatop loopback REF_CLK1 for ENET1,
 * clear gpr1[13], set gpr1[17].
 */
clrsetbits_le32(&iomuxc_regs->gpr[1], IOMUX_GPR1_FEC1_MASK,
                IOMUX_GPR1_FEC1_CLOCK_MUX1_SEL_MASK);
/*
 * Use 50M anatop loopback REF_CLK2 for ENET2,
 * clear gpr1[14], set gpr1[18].
 */
if (!check_module_fused(MODULE_ENET2)) {
    clrsetbits_le32(&iomuxc_regs->gpr[1], IOMUX_GPR1_FEC2_MASK,
                    IOMUX_GPR1_FEC2_CLOCK_MUX1_SEL_MASK);
}
```

这段代码在配置IOMUXC的GPR1寄存器。i.MX6ULL的IOMUXC模块有一组GPR（General Purpose Register）寄存器，GPR1专门用于以太网时钟源选择。fec1对应gpr1[13]和gpr1[17]，fec2对应gpr1[14]和gpr1[18]。

`clrsetbits_le32`是个位操作宏，先clear指定的位，再set指定的位。对于fec1，它清除`IOMUX_GPR1_FEC1_MASK`，然后设置`IOMUX_GPR1_FEC1_CLOCK_MUX1_SEL_MASK`。这个操作的结果是把fec1的时钟源切换到PLL3的输出。

接下来是`enable_fec_anatop_clock`函数调用：

```c
ret = enable_fec_anatop_clock(0, ENET_50MHZ);
if (ret)
    return ret;

if (!check_module_fused(MODULE_ENET2)) {
    ret = enable_fec_anatop_clock(1, ENET_50MHZ);
    if (ret)
        return ret;
}
```

这个函数的第一个参数是FEC控制器的索引，0表示fec1，1表示fec2。第二个参数是时钟频率，`ENET_50MHZ`表示50MHz。函数内部会配置Anatop的对应寄存器，把PLL3的输出分频成50MHz。

最后一行`enable_enet_clk(1)`是使能以太网时钟树的根时钟。这个函数调用之后，50MHz的时钟就开始输出到fec1和fec2的REF_CLK引脚了。

时钟配置有个常见的坑：如果你的PHY芯片需要外部时钟（比如LAN8720A某些型号），但你配置成了内部时钟，或者反过来，PHY都无法正常工作。解决方法是仔细阅读原理图和PHY芯片手册，确认时钟来源到底是外部还是内部。

## 引脚冲突：RMII复用的那些坑

i.MX6ULL的以太网引脚支持多种复用模式，包括RMII、MII、甚至可以复用成普通GPIO或其他外设。引脚配置错误是网络移植中最常见的问题之一。

我们的板子使用RMII模式，所以pinctrl配置是：

```
pinctrl_enet1: enet1grp {
	fsl,pins = <
		MX6UL_PAD_ENET1_RX_EN__ENET1_RX_EN	0x1b0b0
		MX6UL_PAD_ENET1_RX_ER__ENET1_RX_ER	0x1b0b0
		MX6UL_PAD_ENET1_RX_DATA0__ENET1_RDATA00	0x1b0b0
		MX6UL_PAD_ENET1_RX_DATA1__ENET1_RDATA01	0x1b0b0
		MX6UL_PAD_ENET1_TX_EN__ENET1_TX_EN	0x1b0b0
		MX6UL_PAD_ENET1_TX_DATA0__ENET1_TDATA00	0x1b0b0
		MX6UL_PAD_ENET1_TX_DATA1__ENET1_TDATA01	0x1b0b0
		MX6UL_PAD_ENET1_TX_CLK__ENET1_REF_CLK1	0x4001b031
	>;
};

pinctrl_enet2: enet2grp {
	fsl,pins = <
		MX6UL_PAD_GPIO1_IO07__ENET2_MDC		0x1b0b0
		MX6UL_PAD_GPIO1_IO06__ENET2_MDIO	0x1b0b0
		MX6UL_PAD_ENET2_RX_EN__ENET2_RX_EN	0x1b0b0
		MX6UL_PAD_ENET2_RX_ER__ENET2_RX_ER	0x1b0b0
		MX6UL_PAD_ENET2_RX_DATA0__ENET2_RDATA00	0x1b0b0
		MX6UL_PAD_ENET2_RX_DATA1__ENET2_RDATA01	0x1b0b0
		MX6UL_PAD_ENET2_TX_EN__ENET2_TX_EN	0x1b0b0
		MX6UL_PAD_ENET2_TX_DATA0__ENET2_TDATA00	0x1b0b0
		MX6UL_PAD_ENET2_TX_DATA1__ENET2_TDATA01	0x1b0b0
		MX6UL_PAD_ENET2_TX_CLK__ENET2_REF_CLK2	0x4001b031
	>;
};
```

注意fec1和fec2的引脚数量不同。fec1有8个引脚，fec2有10个引脚。差异在哪里？fec2多了MDC和MDIO两个引脚。这是为什么呢？

因为fec1和fec2共享MDIO总线，而MDIO总线是从fec2引出的。i.MX6ULL的设计是这样的：MDIO控制信号默认从fec2的GPIO1_IO06和GPIO1_IO07引出，fec1通过内部连接访问同一条总线。所以在fec1的pinctrl里你看不到MDC/MDIO引脚，但在fec2的pinctrl里可以看到。

引脚配置的每个条目都有三个部分：宏名、功能名、配置值。比如`MX6UL_PAD_ENET1_RX_EN__ENET1_RX_EN 0x1b0b0`，`MX6UL_PAD_ENET1_RX_EN`是pad名，`ENET1_RX_EN`是功能名，`0x1b0b0`是配置值。

配置值`0x1b0b0`的含义需要查i.MX6ULL的参考手册，但大致来说：`0x1b`是上下拉和驱动强度配置，`0x0b0`是 slew rate和 keep alive 等配置。最后一个配置值有点特殊：`0x4001b031`。这个值比其他的多了`0x4000`部分，表示这个引脚有特殊配置。对于`ENET1_REF_CLK1`和`ENET2_REF_CLK2`，这个特殊配置是为了使能内部时钟输出模式。

引脚冲突是网络移植的常见坑。如果你的板子同时启用了多个外设，可能会发现以太网引脚和其他外设引脚冲突了。解决方法是仔细检查原理图，确认每个引脚的复用功能，然后在设备树里正确配置pinctrl。

## PHY复位时序：为什么200ms还不够

PHY复位时序是网络移植中最容易被忽视的问题，但也是最重要的。如果PHY没有正确复位，它可能处于未知状态，表现为能初始化但link不起来，或者偶尔能工作但不稳定。

我们的设备树配置了200ms的复位时间和200ms的复位后延迟：

```
phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
phy-reset-duration = <200>;
phy-reset-post-delay = <200>;
```

这个时序的含义是：先把GPIO5_7拉低200ms，然后拉高，等待200ms，之后才开始访问PHY。拉低期间PHY处于复位状态，所有寄存器恢复默认值。拉高后PHY开始初始化，需要一段时间才能稳定。

200ms是一个保守值，大多数PHY芯片的数据手册要求的复位时间都比这短。但这里有个问题：不同PHY芯片的复位要求不同，有些可能只需要10ms，有些可能需要50ms。用200ms虽然浪费点时间，但能覆盖大多数情况。

但事情到这里还没完。复位结束后的等待时间同样重要。PHY复位后需要重新autonegotiate（自动协商），这个过程可能需要几秒钟。如果PHY还没完成autonegotiate你就开始发数据，结果就是丢包或者连接失败。

U-Boot的PHY驱动有个机制叫`phy_startup`，它会等待PHY autonegotiate完成。但如果你的PHY芯片autonegotiate特别慢，可能需要增加超时时间。另一种情况是，你连接的对端设备也慢，导致整体autonegotiate时间很长。这种情况下你可能需要手动设置速度和双工模式，跳过autonegotiate。

PHY复位还有个常见的坑：GPIO_ACTIVE_LOW的问题。如果你的原理图设计是高电平复位，但你写成了`GPIO_ACTIVE_LOW`，结果就是PHY永远处于复位状态，永远不工作。反过来也一样。所以写设备树前一定要确认原理图上的复位极性。

## 双网卡配置：eth0和eth1如何共存

i.MX6ULL有两个FEC控制器，理论上可以配置成两个独立的网络接口。但实际使用中有些细节需要注意。

第一个问题是网卡命名。U-Boot默认按照设备树里fec节点的出现顺序来命名网卡，先出现的叫eth0，后出现的叫eth1。如果你想改变顺序，可以在设备树里调整fec1和fec2节点的顺序。

第二个问题是MAC地址。每个网卡应该有唯一的MAC地址，否则网络交换机会因为地址冲突而丢包。U-Boot的环境变量`ethaddr`和`eth1addr`分别指定eth0和eth1的MAC地址。你可以用`setenv ethaddr 02:00:00:00:00:01`这样的命令来设置。

第三个问题是默认网卡的指定。U-Boot有个环境变量`ethact`，指定当前活动的网卡。你可以用`setenv ethact eth0`来切换。如果你不设置，U-Boot会自动选择第一个能用的网卡。

双网卡配置有个实用技巧：你可以把eth0用于tftp下载内核，eth1用于NFS挂载根文件系统。这样两个网络功能互不干扰，调试时更方便。或者你可以把eth0用于外网访问，eth1用于板间通信，实现网络隔离。

## 网络调试命令：U-Boot里的瑞士军刀

U-Boot提供了一组网络调试命令，这些命令在调试网络问题时非常实用。

`ping`命令是最基础的，测试网络连通性。`ping 192.168.1.1`会发送ICMP echo请求到指定IP。如果ping通，说明链路层和网络层都正常。如果ping不通，问题可能在PHY配置、IP配置、或者网线连接上。

`dhcp`命令可以从DHCP服务器获取IP地址。`dhcp eth0`会从eth0发起DHCP请求，成功后会设置`ipaddr`、`netmask`、`serverip`等环境变量。如果你的网络环境有DHCP服务器，用这个命令比手动设置IP方便得多。

`tftp`命令用于从TFTP服务器下载文件。`tftp 80800000 uImage`会把服务器上的uImage文件下载到内存地址0x80800000。tftp是嵌入式开发中最常用的文件传输方式，比串口下载快得多。

`nfs`命令用于挂载NFS根文件系统。`nfs 80800000 192.168.1.100:/path/to/rootfs`会把服务器上的rootfs目录加载到内存。NFS挂载在开发阶段特别有用，你可以直接在主机上修改文件，板子上立即生效，不需要反复烧录。

`mii`命令是MDIO调试的瑞士军刀。`mii list`列出检测到的PHY设备，`mii info`显示PHY的详细信息，`mii read <addr> <reg>`读取PHY寄存器，`mii write <addr> <reg> <value>`写入PHY寄存器。当你怀疑MDIO总线有问题时，用这些命令可以快速定位。

`ethact`命令切换当前活动的网卡。`ethact eth0`切换到eth0，之后的网络命令都通过eth0执行。`printenv ethact`查看当前活动的网卡。

## 与正点原子的网络配置对比

正点原子的imx6ull开发板网络配置和我们有一些差异，了解这些差异有助于你理解不同板型的设计思路。

最大的差异是PHY芯片的选择。正点原子的板子常用LAN8720A，而我们用的是KSZ8081。LAN8720A是SMSC公司的产品，已经被Microchip收购。它的功能和KSZ8081类似，但寄存器布局和配置方法有所不同。特别是LED模式和时钟配置，两者的数据手册要求不一样。

第二个差异是PHY地址配置。正点原子的板子通常把两个PHY的地址都设为0和1，而我们的板子是1和2。这完全是板级设计的差异，没有优劣之分，只要设备树配置和硬件一致就行。

第三个差异是时钟源选择。有些正点原子的板子设计用外部50MHz晶振，而我们的板子用内部PLL。外部晶振的优点是时钟稳定性好，缺点是增加了硬件成本和PCB面积。内部PLL的优点是节省硬件，缺点是需要软件配置时钟树。

第四个差异是复位GPIO的选择。正点原子的板子可能用GPIO1_IOXX作为PHY复位，而我们的板子用GPIO5_7和GPIO5_8。这也是板级设计的差异，要根据原理图确认。

不管用什么板子，网络移植的核心步骤是一样的：确认PHY型号、配置设备树、设置pinctrl、配置时钟、配置复位GPIO、验证MDIO通信。只要这些步骤都正确，网络就能正常工作。

## 写在最后

网络移植是U-Boot移植中最复杂的部分之一，涉及硬件、时钟、引脚、驱动多个层面。但这也是最值得投入时间的部分，因为一旦网络调通了，后续的开发效率会大幅提升。

你现在应该理解了MAC和PHY的关系、MDIO总线的作用、RMII和MII的区别、PHY复位时序的重要性。这些东西在数据手册里都有写，但分散在各个章节，很少有人系统地整理出来。这篇文章希望能把这些知识点串起来，给你一个完整的网络移植图景。

网络调通后，你的板子就有了"联网"的能力。下一篇文章，我们将利用这个能力来做一件更有意思的事情——让板子在启动时显示你的Logo。这不仅仅是美观，更是产品化的第一步。准备好让你的板子"颜值"提升了吗？

## 参考资源

- [正点原子ALPHA开发板（IMX6ULL）移植Uboot5.4（三）网络驱动修改](https://blog.csdn.net/weixin_45740246/article/details/144431066)
- [【uboot】imx6ull uboot移植LAN8720A网卡驱动](https://cloud.tencent.com/developer/article/2097099)
- [I.MX6ULL FEC网络驱动设备树配置详解](https://blog.csdn.net/weixin_33239721/article/details/157816867)
- KSZ8081数据手册 - Microchip官方文档
- i.MX6ULL参考手册 - NXP官方文档
