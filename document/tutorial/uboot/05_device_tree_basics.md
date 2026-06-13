---
title: 设备树基础
---

# 设备树基础：从硬编码噩梦到硬件描述分离

## 为什么要谈设备树

老实说，设备树这个概念刚接触的时候真的让人头大。一堆花括号、各种莫名其妙的属性、那个`compatible`到底在匹配什么东西、引脚复用配置里的那些十六进制数是什么鬼——如果你也是这种感受，放心，我们当年都是这么过来的。

但问题是，你绕不开它。在U-Boot移植过程中，设备树就是那本"硬件使用说明书"。CPU怎么知道你的eMMC接在哪个引脚上？怎么知道你用的是这个PHY芯片而不是那个PHY芯片？怎么知道你的LCD屏幕分辨率是1024x600而不是800x480？答案全在设备树里。

更妙的是，设备树解决了嵌入式开发史上一个巨大的痛点：硬编码。在设备树出现之前，硬件配置是写死在代码里的。你想换个eMMC容量？改代码重新编译。你想换个PHY芯片地址？改代码重新编译。你想维护同一款芯片的十种不同板型？恭喜你，你要维护十份几乎完全相同的代码，只有几个数字不同。这在工程上简直是灾难。（猜猜设备树在历史的来源？去搜下Linus，对，就那个Linux Maintainer老大哥，咋喷ARM社区到狗血领头的）

## 从硬编码到设备树：一场革命

让我给你讲个故事。在2005年左右做嵌入式开发是什么体验？假设你的板子上有一个I2C设备，地址是0x50。你要做的事情是：

1. 找到板级初始化代码（通常在`arch/arm/mach-xxx/`下面的某个文件）
2. 找到I2C设备的注册函数
3. 硬编码设备地址到代码里
4. 重新编译整个内核
5. 烧录测试

然后有一天，硬件工程师跑过来说"嘿，我们换个I2C设备，地址改成0x51了"。你就得把上面这套流程再来一遍。更惨的是，如果你维护的是同一款芯片的不同板型，你就得维护多份几乎相同的代码，只有几个参数不同。这就是为什么那个年代的Linux内核源码里，`arch/arm/mach-*`目录下的文件数量爆炸式增长。

ARM Linux早期使用的是ATAG机制——参数标签列表。这玩意儿的功能很有限，基本上只能传内存大小、命令行参数这些基础信息。复杂的硬件描述？别想了。

2008年，PowerPC架构已经成功迁移到了设备树机制，效果很好。2010年，PowerPC维护者Grant Likely提议ARM也跟进，从ATAG转向设备树描述硬件。这在当时引起了不小的争议，因为这意味着要改动大量的板级代码。但历史证明，这个决定是正确的。2011到2012年间，ARM Linux开始大规模迁移到设备树，ATAG机制逐步被废弃。

设备树的核心思想很简单：把硬件描述从代码中分离出来，用一种专门的格式（DTS文件）来描述。硬件不变，设备树就不变；硬件变了，只需要改设备树，不需要改代码。同一个内核镜像，配上不同的设备树，就可以运行在不同的板子上——这在以前是不可想象的。

U-Boot对设备树的支持是从v1.1.3开始的，通过`CONFIG_OF_LIBFDT`选项启用。但有趣的是，U-Boot和Linux在设备树方面并不是完全同步的。某些板级绑定在两个项目中仍然存在差异，为了解决这个问题，U-Boot维护了一个从Linux内核同步的设备树子目录，通过devicetree-rebasing机制保持更新。你在U-Boot源码里看到的`*-u-boot.dtsi`文件，就是专门用来添加U-Boot特定配置的，不会和Linux内核的设备树冲突。

## DTS文件结构：.dts vs .dtsi

好了，历史课结束。我们来聊聊DTS文件本身。

首先你要搞清楚两个概念：`.dts`文件和`.dtsi`文件。`.dts`是设备树源文件（Device Tree Source），`.dtsi`是设备树包含文件（Device Tree Source Include）。这个区别就像C语言里的`.c`和`.h`——`.dtsi`是用来被包含的公共定义，`.dts`是具体的板级配置。

来看我们的板子文件：

```dts
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
```

这个文件的结构非常典型。第一行`/dts-v1/;`声明我们使用的是设备树语法版本1，这是现在通用的格式。然后是三个`#include`，分别包含了：

1. `imx6ull.dtsi`：i.MX6ULL芯片的基础设备树定义，包含CPU、内存控制器、各种外设的基本信息
2. `imx6ull-aes.dtsi`：我们板子特定的硬件配置
3. `imx6ull-14x14-evk-u-boot.dtsi`：U-Boot特定的配置

然后是根节点`/`，里面定义了`model`和`compatible`两个属性。`model`就是一个人类可读的描述，告诉你这是什么板子；`compatible`就重要了，它是驱动匹配的关键。

你会发现这个`.dts`文件非常简洁，只有45行。真正的硬件配置都在`imx6ull-aes.dtsi`里。这就是良好的分层设计：`.dts`文件只定义板子级别的信息，具体的硬件配置放在`.dtsi`里，这样可以方便地复用。

## 常用属性详解

设备树里的节点和属性看起来很神秘，但其实每个属性都有明确的用途。我们来拆解几个最常用的。

### compatible：设备身份的身份证

`compatible`属性可能是设备树里最重要的属性了。它用于驱动程序和设备之间的匹配。比如：

```dts
compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";
```

这个属性有两个值：`"fsl,imx6ull-14x14-evk"`和`"fsl,imx6ull"`。驱动程序会按照从左到右的顺序尝试匹配，先找最具体的（第一个），找不到就用更通用的（第二个）。这个机制叫"compatible向后兼容"，它的意思就是：这个板子首先是一块"imx6ull-14x14-evk"，其次它也是一块"imx6ull"。

对于I2C设备，比如我们的WM8960音频编解码器：

```dts
codec: wm8960@1a {
    #sound-dai-cells = <0>;
    compatible = "wlf,wm8960";
    reg = <0x1a>;
    ...
};
```

这里的`compatible = "wlf,wm8960"`告诉驱动：这是一个Wolfson Microelectronics（现在是Cirrus Logic）生产的WM8960芯片。驱动程序会根据这个字符串来查找对应的驱动代码。

### reg：地址和大小

`reg`属性用于描述设备的寄存器地址或内存映射范围。比如我们板子的内存定义：

```dts
memory@80000000 {
    device_type = "memory";
    reg = <0x80000000 0x20000000>;
};
```

这里的`reg = <0x80000000 0x20000000>`表示：内存的起始地址是`0x80000000`（512MB），大小是`0x20000000`（512MB）。i.MX6ULL的DDR内存控制器把外部SDRAM映射到了这个地址空间，这是芯片的物理设计决定的。

你可能会问：`@80000000`和`reg`里的地址有什么区别？`@80000000`是节点的单元地址（unit-address），它必须和`reg`里的第一个地址匹配。这个约定是为了让设备树编译器（DTC）能够快速定位节点，也方便人类阅读。

对于I2C设备，`reg`的含义稍有不同：

```dts
codec: wm8960@1a {
    compatible = "wlf,wm8960";
    reg = <0x1a>;
    ...
};
```

这里`reg = <0x1a>`表示这个设备在I2C总线上的地址是0x1A。注意I2C地址只有7位或10位，所以`reg`只需要一个值。

### status：开关设备

`status`属性可能是最简单的属性了，它只有两个常用值：`"okay"`和`"disabled"`。

```dts
&csi {
    status = "disabled";
    ...
};

&ov5640 {
    status = "disabled";
    ...
};
```

在我们的板子上，摄像头接口（CSI）和OV5640摄像头都被禁用了。为什么？因为我们可能还没有接摄像头，或者调试时不想让它干扰。当你要启用这些设备时，只需要把`status`改成`"okay"`就可以了，不用修改任何代码。

这个机制在硬件调试时非常实用。你可以先把所有不确定的设备都禁用，然后一个一个启用，逐个排查问题。

### #address-cells和#size-cells：地址解码器

这两个属性可能是设备树里最让人困惑的了，但理解它们之后，你会发现设备树的设计真的很精妙。

```dts
/ {
    #address-cells = <1>;
    #size-cells = <1>;
    ...
};
```

`#address-cells`定义了子节点的`reg`属性中，地址信息占用多少个32位单元（cell）。`#size-cells`定义了长度信息占用多少个cell。

在根节点下，`#address-cells = <1>`和`#size-cells = <1>`表示：子节点的`reg`属性里，地址占1个cell，大小占1个cell。比如内存节点：

```dts
memory@80000000 {
    reg = <0x80000000 0x20000000>;
};
```

这里`0x80000000`是地址（1个cell），`0x20000000`是大小（1个cell）。

但对于某些总线，地址和大小可能需要多个cell来表示。比如64位系统可能需要2个cell来表示地址：

```dts
/ {
    #address-cells = <2>;
    #size-cells = <1>;
    ...
};
```

这样子节点的`reg`就会是`<0x0 0x80000000 0x20000000>`这种格式，高位地址在前。

对于I2C总线这样的简单总线，`#size-cells`通常是0，因为I2C设备没有地址范围的概念：

```dts
i2c2 {
    #address-cells = <1>;
    #size-cells = <0>;

    codec: wm8960@1a {
        reg = <0x1a>;
    };
};
```

这里`#size-cells = <0>`表示I2C设备的`reg`里没有大小信息，只有地址。

## 引脚复用配置：pinctrl子系统

引脚复用（Pin Multiplexing）是嵌入式系统里最容易让人头疼的问题之一。i.MX6ULL这样的芯片，引脚数量远远多于实际封装的管脚数量，所以一个物理引脚往往可以复用为多种功能。比如`UART1_TX_DATA`这个引脚，可以作为UART1的发送引脚，也可以配置成普通GPIO，或者其它外设的信号。

在设备树里，引脚复用配置是通过`pinctrl`子系统来描述的。来看一个例子：

```dts
pinctrl_uart1: uart1grp {
    fsl,pins = <
        MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
        MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
    >;
};
```

这里定义了一个叫`pinctrl_uart1`的引脚配置组，里面有两个引脚。每个引脚配置由两部分组成：引脚名称和配置值。

`MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX`这个宏定义（在`imx6ul-pinfunc.h`里）展开后是一个32位整数，高16位是引脚编号，低16位是复用功能选择。`__`前面是物理引脚名称（PAD），后面是复用功能（MUX）。

后面的`0x1b0b1`是引脚电气配置。这个32位数的每一位都有含义：

- 位0-11：上拉/下拉配置、驱动强度、开漏使能、速度等
- 位12-15：保留位
- 位16-23：额外配置（如施密特触发器）
- 位24-31：保留位

具体到`0x1b0b1`（二进制：0001 1011 0000 1011 0001）：

- `0x1b0`部分配置了引脚的电气特性
- 最后的`0xb1`配置了上拉、驱动等

这些数值是怎么来的？答案是芯片数据手册（Datasheet）。NXP的i.MX6ULL参考手册里有一张巨大的表，列出了每个引脚的所有配置选项和对应的寄存器值。你没看错，这些数字不是瞎填的，每一个位都有数据手册依据。

引脚配置还有一个重要的概念：状态切换。比如我们的eMMC配置：

```dts
&usdhc2 {
    pinctrl-names = "default", "state_100mhz", "state_200mhz";
    pinctrl-0 = <&pinctrl_usdhc2_8bit>;
    pinctrl-1 = <&pinctrl_usdhc2_8bit_100mhz>;
    pinctrl-2 = <&pinctrl_usdhc2_8bit_200mhz>;
    ...
};
```

这里定义了三种状态：默认状态（`default`）、100MHz状态（`state_100mhz`）和200MHz状态（`state_200mhz`）。`pinctrl-0/1/2`分别对应这三个状态的引脚配置。为什么要这样？因为eMMC在不同的工作频率下需要不同的引脚电气特性。低速时用默认配置，中速时切换到100MHz配置，高速时切换到200MHz配置。驱动程序会根据实际工作频率自动切换状态，这是硬件优化的一个重要手段。

你可能注意到了，每个引脚配置后面都有一个类似`0x1b0b1`这样的数字。这个数字是引脚的电气特性配置，包括驱动强度、上拉下拉、转换速率等。不同频率下，这个数值是不同的，因为高速信号需要更严格的时序控制。

比如在默认状态下，eMMC引脚配置是`0x17059`，而在200MHz状态下是`0x170f9`。这两个数值的差异主要在驱动强度和转换速率上，高速模式下需要更强的驱动和更快的转换速率。

## 时钟配置：CCM和PLL原理

嵌入式系统的时钟管理是一个深不见底的话题，但我们先从设备树的角度来看看是怎么描述的。

i.MX6ULL的时钟系统非常复杂，有一个叫CCM（Clock Controller Module）的模块，里面有多个PLL（Phase-Locked Loop，锁相环）和各种分频器。PLL负责把外部晶振（通常是24MHz）倍频到更高的频率，然后分频器再把这些高频时钟分配给各个外设。

我们的设备树里有这样一段：

```dts
&clks {
    assigned-clocks = <&clks IMX6UL_CLK_PLL3_PFD2>,
                      <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
    assigned-clock-rates = <320000000>, <786432000>;
};
```

这段话的意思是：把`PLL3_PFD2`的频率设置为320MHz，把`PLL4_AUDIO_DIV`的频率设置为786.432MHz。为什么是786.432MHz这个奇怪的数字？因为音频采样率（如44.1kHz、48kHz）需要精确的时钟分频，786.432MHz是音频时钟树的一个常用频率，它可以精确分频出各种音频采样率。

时钟配置的一个重要原则是：不是所有外设都需要最高的时钟频率。过高的时钟频率会增加功耗和EMI（电磁干扰），所以应该根据实际需求设置合适的频率。比如SAI2音频接口的配置：

```dts
&sai2 {
    assigned-clocks = <&clks IMX6UL_CLK_SAI2_SEL>,
                      <&clks IMX6UL_CLK_SAI2>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
    assigned-clock-rates = <0>, <12288000>;
    ...
};
```

这里`SAI2_SEL`选择时钟源（`PLL4_AUDIO_DIV`），`SAI2`设置分频后的频率（12.288MHz）。注意第一个`assigned-clock-rates`是0，表示"自动选择"，也就是只选择时钟源但不设置具体频率。

你可能还注意到了`assigned-clock-parents`这个属性。i.MX6ULL的时钟系统是多级的，每个时钟可能从多个源头获取信号。比如SAI2可以选择从PLL、OSC、或者其它分频器获取时钟。`assigned-clock-parents`就是用来选择时钟源的。

时钟配置中最让人头疼的部分可能是时钟ID。`IMX6UL_CLK_PLL3_PFD2`这样的宏定义在`imx6ul-clock.h`里，每个ID对应CCM里的一个具体时钟。这些ID是芯片设计时定义的，你无法更改，只能在驱动代码里查找对应关系。

## 实战：分析我们的imx6ull-aes.dts设备树

现在我们来完整分析一下我们板子的设备树，看看它是如何描述硬件的。

首先来看`.dts`文件：

```dts
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

这个文件有几个值得注意的技巧。首先是`&csi`、`&ov5640`这样的语法，这叫节点引用（node reference）。`&`符号表示引用在包含文件里定义的节点，然后在大括号里添加或覆盖属性。这是一种非常优雅的修改方式，不需要复制整个节点定义，只需要修改你关心的属性。

其次是`/delete-node/ &sim2;`这个语法。SIM卡接口在我们的板子上不存在，所以直接删除这个节点。设备树编译器会从最终的二进制设备树（DTB）里移除这个节点，就像它从未存在过一样。

最后是`usdhc2`节点。这里重写了`pinctrl-names`和`pinctrl-0/1/2`属性，覆盖了`imx6ull-aes.dtsi`里的定义。这是为了启用8位宽度的eMMC接口（`bus-width = <8>`）。`non-removable`表示eMMC是焊在板子上的，不可热插拔，驱动程序可以据此优化行为。

接下来看`.dtsi`文件，这里包含了大部分硬件配置：

```dts
/ {
    aliases {
        spi5 = &{/spi-4};
    };

    chosen {
        stdout-path = &uart1;
    };

    memory@80000000 {
        device_type = "memory";
        reg = <0x80000000 0x20000000>;
    };
    ...
};
```

`aliases`节点定义了设备的别名。`spi5 = &{/spi-4}`是一个特殊的语法，引用了一个绝对路径节点（`/spi-4`）。这个节点是用GPIO模拟的SPI总线，因为i.MX6ULL的硬件SPI不够用。

`chosen`节点是启动参数的传递渠道。`stdout-path = &uart1`表示控制台输出到UART1，这样U-Boot的早期启动信息就能通过串口打印出来。这对于调试非常重要，没有它你就看不到启动日志。

然后是各种外设节点，比如网络接口：

```dts
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
```

`fec1`是i.MX6ULL的第一个以太网控制器（Fast Ethernet Controller）。`phy-mode = "rmii"`表示使用RMII接口与PHY芯片通信，这是i.MX6ULL常用的网络接口方式（MII需要更多引脚）。

`phy-handle = <&ethphy0>`引用了MDIO总线上的PHY设备描述。`phy-reset-gpios`定义了PHY复位信号：GPIO5_7，低电平有效。`phy-reset-duration`和`phy-reset-post-delay`定义了复位时序，PHY芯片需要正确的复位序列才能正常工作。`phy-supply = <&reg_peri_3v3>`表示PHY芯片由3.3V外设电源供电。

再看MDIO总线和PHY设备定义：

```dts
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

注意`mdio`节点定义在`fec2`节点里面。MDIO是管理数据输入输出总线，用于配置PHY芯片。`#address-cells = <1>`和`#size-cells = <0>`表示MDIO总线上的设备只有地址，没有地址范围。

`ethphy0`和`ethphy1`是两片KSZ8091RNB PHY芯片，`compatible = "ethernet-phy-id0022.1560"`中的`0022.1560`是PHY的ID号（IEEE OUI为00:22，型号为15:60）。`reg = <2>`和`reg = <1>`是PHY在MDIO总线上的地址。`micrel,led-mode = <1>`是Micrel（现在是Microchip）PHY特有的属性，配置LED指示灯行为。

`clocks = <&clks IMX6UL_CLK_ENET_REF>`定义了PHY的参考时钟源。RMII接口需要一个50MHz的参考时钟，这个时钟可以由MAC（网络控制器）提供，也可以由外部晶振提供。这里选择由MAC提供。

## 与正点原子设备树的对比

正点原子（ALIENTEK）是国内知名的嵌入式开发板厂商，他们的i.MX6ULL开发板也使用设备树。对比一下我们的设备和他们的设备树，你会发现一些有趣的设计差异。

首先，正点原子的设备树文件命名通常是`imx6ull-alientek-emmc.dts`，而我们是`imx6ull-aes.dts`。命名风格不同，但遵循同样的规则：芯片名-板型名.dts。

在结构上，正点原子的设备树倾向于把更多配置写在`.dts`文件里，而我们将大部分硬件配置放在`.dtsi`里。这两种方式没有优劣之分，只是组织风格的差异。我们的方式更强调"板级配置与芯片级配置分离"，他们的方式更强调"一个文件看清板子全貌"。

在时钟配置上，正点原子的设备树通常设置更多的时钟固定频率：

```dts
&clks {
    assigned-clocks = <&clks IMX6UL_CLK_PLL3_PFD2>,
                      <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
    assigned-clock-rates = <320000000>, <786432000>;
};
```

这部分我们是一致的。但正点原子的某些板型还会固定更多外设时钟，如UART、I2C等。我们的策略是让驱动程序自动选择时钟，这样更灵活，功耗也更好控制。

在引脚配置上，正点原子的设备树倾向于使用更宽松的电气特性（如更大的驱动强度、更快的转换速率），而我们倾向于根据实际信号要求选择合适的配置。例如，我们的eMMC 200MHz配置是`0x170f9`，而正点原子可能用`0x1b0f9`（更强的驱动）。这种差异不会导致功能问题，但在EMI测试时可能会有区别。

一个显著差异是SIM卡接口。正点原子的某些板型支持SIM卡，所以他们的设备树里保留了`sim2`节点：

```dts
&sim2 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_sim2>;
    assigned-clocks = <&clks IMX6UL_CLK_SIM_SEL>;
    assigned-clock-parents = <&clks IMX6UL_CLK_SIM_PODF>;
    assigned-clock-rates = <240000000>;
    ...
};
```

我们的板子不需要SIM卡功能，所以直接删除了`sim2`节点。这种"按需启用"的策略让设备树更简洁，也避免了不必要的外设初始化。

## 设备树对移植的好处

到这里，你应该能体会到设备树对嵌入式系统移植的巨大价值了。让我总结一下：

首先是代码复用。有了设备树，同一个U-Boot镜像可以运行在多个不同的板子上，只要给它们配上不同的设备树文件。这在产品线维护时是巨大的优势——你不需要为每个板型维护一套独立的代码。

其次是调试效率。硬件配置修改不需要重新编译代码，只需要修改设备树然后重新编译DTB。DTB的编译速度比完整的代码编译快得多，这大大缩短了调试周期。

然后是可维护性。设备树用结构化的方式描述硬件，比硬编码的板级初始化函数更易读、更易维护。新人接手项目时，看设备树比看一大板级初始化代码要轻松得多。

最后是社区协作。设备树已经成为Linux和U-Boot的标准硬件描述方式，这意味着你可以直接使用社区贡献的设备树，或者把自己的设备树贡献回社区。正点原子、NXP官方、以及其他开发者的设备树都可以作为参考，这大大降低了开发门槛。

## 写在最后

设备树的学习曲线确实陡峭，这是不争的事实。一堆宏定义、莫名其妙的十六进制数、复杂的时钟树、怎么也记不住的属性名称——刚接触时，谁都会有点崩溃。

但好消息是，设备树是一个"投入一次，长期受益"的技能。一旦你理解了它的基本原理，后面遇到任何新的芯片或板子，你都能快速上手。因为设备树的核心思想——硬件描述与代码分离——是通用的。

在下一篇文章里，我们将深入到实际的移植过程中。你会看到如何从零开始为一个新板子编写设备树，如何验证设备树配置是否正确，以及如何调试设备树相关的问题。那将是一个真正的"从原理到实践"的过程。

但在此之前，我建议你做一件事情：打开我们项目的`patches/uboot-imx/charlies_board.patch`，仔细读一下`imx6ull-aes.dtsi`里的每个节点和属性。对照着i.MX6ULL的参考手册和板子原理图，尝试理解每个配置的含义。这个过程可能有点枯燥，但你会发现，设备树其实是一份非常精确的"硬件说明书"——它描述的每一条信息，都能在硬件上找到对应的实体。

准备好了吗？让我们继续深入U-Boot的世界。
