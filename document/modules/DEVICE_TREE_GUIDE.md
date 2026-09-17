# IMX-Forge 设备树配置指南

## 目录

- [第一部分：设备树基础回顾](#第一部分设备树基础回顾)
  - [1.1 什么是设备树](#11-什么是设备树)
  - [1.2 DTS/DTC/DTB关系](#12-dtsdtcdtb关系)
  - [1.3 基本语法](#13-基本语法)
  - [1.4 设备树编译工具](#14-设备树编译工具)

- [第二部分：Alpha板设备树详解](#第二部分alpha板设备树详解)
  - [2.1 主设备树文件](#21-主设备树文件)
  - [2.2 设备树包含文件](#22-设备树包含文件)
  - [2.3 关键外设配置](#23-关键外设配置)

- [第三部分：常用外设配置](#第三部分常用外设配置)
  - [3.1 LCD移植](#31-lcd移植)
  - [3.2 网络移植](#32-网络移植)
  - [3.3 存储设备（eMMC/SD）](#33-存储设备emmc)
  - [3.4 GPIO配置](#34-gpio配置)
  - [3.5 I2C设备](#35-i2c设备)
  - [3.6 SPI设备](#36-spi设备)
  - [3.7 UART配置](#37-uart配置)

- [第四部分：自定义板卡移植步骤](#第四部分自定义板卡移植步骤)
  - [4.1 从Alpha板开始](#41-从alpha板开始)
  - [4.2 修改设备树](#42-修改设备树)
  - [4.3 验证步骤](#43-验证步骤)
  - [4.4 常见问题](#44-常见问题)

- [第五部分：设备树调试](#第五部分设备树调试)
  - [5.1 语法检查](#51-语法检查)
  - [5.2 编译验证](#52-编译验证)
  - [5.3 运行时调试](#53-运行时调试)

---

## 第一部分：设备树基础回顾

### 1.1 什么是设备树

设备树（Device Tree）是一种用于描述硬件配置的数据结构，它将硬件的详细信息和操作系统内核分离，使得同一个内核镜像可以运行在不同的硬件平台上。

在设备树出现之前，硬件配置信息是硬编码在内核源码中的。每开发一块新板子，就需要修改内核代码并重新编译。这种方式带来了诸多问题：

- 代码维护困难：同一款芯片的不同板型需要维护多份代码
- 移植效率低：硬件改动需要重新编译整个内核
- 社区协作差：厂商的硬件配置难以合并到主线内核

设备树通过独立的配置文件（DTS）来描述硬件，解决了这些问题：

- 硬件配置独立于内核代码
- 同一内核可运行在不同板子上
- 硬件改动只需修改设备树文件

### 1.2 DTS/DTC/DTB关系

设备树涉及三种文件格式，它们之间有明确的转换关系：

```
┌─────────────┐    dtc编译器    ┌─────────────┐
│  DTS源文件   │  ──────────>   │   DTB二进制  │
│  (.dts)     │                │   (.dtb)     │
│             │    dtc反编译    │             │
│  可读文本   │  <──────────    │  机器可读   │
└─────────────┘                 └─────────────┘
      │
      │ #include指令
      │
      v
┌─────────────┐
│  DTSI包含   │
│  (.dtsi)    │
│  公共定义    │
└─────────────┘
```

**DTS (Device Tree Source)**：设备树源文件，人类可读的文本格式，包含具体的硬件配置。文件名通常格式为`<芯片名>-<板型名>.dts`，如`imx6ull-aes.dts`。

**DTSI (Device Tree Source Include)**：设备树包含文件，类似于C语言的头文件，包含公共的硬件定义。如`imx6ull.dtsi`包含i.MX6ULL芯片的基础定义。

**DTB (Device Tree Blob)**：设备树二进制文件，由DTC编译器生成，是内核和U-Boot实际使用的格式。

**DTC (Device Tree Compiler)**：设备树编译器，用于DTS和DTB之间的转换。

### 1.3 基本语法

#### 1.3.1 节点定义

设备树的基本结构是节点（node），节点可以包含属性（property）和子节点。

```dts
/ {
    node1 {
        property1 = "value";
        property2 = <0x12345678>;
        child-node {
            child-property = <1>;
        };
    };
};
```

- `/`：根节点，所有其他节点都是根节点的子孙
- `node1`：节点名称，可以是任意合法的标识符
- `property`：属性，包含属性名和属性值
- `child-node`：子节点

#### 1.3.2 节点引用

使用`&`符号引用已定义的节点，然后添加或覆盖属性：

```dts
// 包含文件中定义
&uart1 {
    status = "okay";
};

// 或者引用完整路径
&{/soc/aips-bus@02000000/spba-bus@02000000/uart@02020000} {
    status = "okay";
};
```

#### 1.3.3 常用属性

**compatible**：设备兼容性字符串，用于驱动匹配

```dts
compatible = "fsl,imx6ull-uart", "fsl,imx6q-uart";
```

驱动程序会按照从左到右的顺序尝试匹配，先查找最具体的，找不到再用更通用的。

**reg**：地址和大小信息

```dts
memory@80000000 {
    device_type = "memory";
    reg = <0x80000000 0x20000000>;  // 起始地址 大小
};
```

**status**：设备状态

```dts
status = "okay";      // 启用设备
status = "disabled";  // 禁用设备
```

**#address-cells 和 #size-cells**：地址和长度配置

```dts
/ {
    #address-cells = <1>;  // 子节点reg中地址占1个cell
    #size-cells = <1>;     // 子节点reg中大小占1个cell
};
```

#### 1.3.4 pinctrl子系统

引脚复用配置是设备树中最复杂的部分之一：

```dts
pinctrl_uart1: uart1grp {
    fsl,pins = <
        MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
        MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
    >;
};
```

每行配置包含两部分：
- 引脚复用宏（如`MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX`）
- 电气特性配置值（如`0x1b0b1`）

### 1.4 设备树编译工具

#### 1.4.1 编译DTS到DTB

```bash
# 基本编译
dtc -I dts -O dtb -o output.dtb input.dts

# 包含依赖目录
dtc -I dts -O dtb -o output.dtb input.dts \
    -i arch/arm/boot/dts

# 添加版本信息
dtc -I dts -O dtb -o output.dtb input.dts \
    -i arch/arm/boot/dts \
    -d output.dtb.d
```

#### 1.4.2 反编译DTB到DTS

```bash
# 反编译DTB
dtc -I dtb -O dts -o output.dts input.dtb

# 查看DTB内容
dtc -I dtb -O dts /boot/imx6ull-14x14-evk.dtb | less
```

#### 1.4.3 语法检查

```bash
# 只检查语法，不生成输出
dtc -I dts -O dtb -o /dev/null input.dts

# 检查并显示详细错误信息
dtc -I dts -O dtb -o output.dtb input.dts -f
```

---

## 第二部分：Alpha板设备树详解

### 2.1 主设备树文件

Alpha板的主设备树文件位于：
- U-Boot：`driver/device_tree/alpha-board/uboot/imx6ull-aes.dts`
- Linux：`driver/device_tree/alpha-board/linux/imx6ull-aes.dts`

文件结构如下：

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

**文件说明**：

1. **版本声明**：`/dts-v1/;`声明使用设备树语法版本1
2. **包含文件**：
   - `imx6ull.dtsi`：i.MX6ULL芯片的基础定义
   - `imx6ull-aes.dtsi`：Alpha板特定的硬件配置
   - `imx6ull-14x14-evk-u-boot.dtsi`：U-Boot特定配置

3. **根节点**：定义板子的model和compatible信息
4. **节点引用**：使用`&`符号引用并修改已定义的节点

### 2.2 设备树包含文件

#### 2.2.1 imx6ull-aes.dtsi结构

这是Alpha板的主要配置文件，包含所有外设的配置：

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

    reg_sd1_vmmc: regulator-sd1-vmmc {
        compatible = "regulator-fixed";
        regulator-name = "VSD_3V3";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        gpio = <&gpio1 9 GPIO_ACTIVE_HIGH>;
        off-on-delay-us = <20000>;
        enable-active-high;
    };

    reg_peri_3v3: regulator-peri-3v3 {
        compatible = "regulator-fixed";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_peri_3v3>;
        regulator-name = "VPERI_3V3";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        gpio = <&gpio5 2 GPIO_ACTIVE_LOW>;
        regulator-always-on;
    };

    reg_can_3v3: regulator-can-3v3 {
        compatible = "regulator-fixed";
        regulator-name = "can-3v3";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        gpios = <&gpio_spi 3 GPIO_ACTIVE_LOW>;
    };
    // ... 更多设备定义
};
```

**重要节点说明**：

- **aliases**：定义设备别名
- **chosen**：启动参数配置，`stdout-path`设置控制台输出设备
- **memory**：内存配置，起始地址0x80000000，大小512MB
- **regulator**：电源管理配置，为SD卡、外设、CAN等提供电源描述

#### 2.2.2 外设节点配置

**I2C设备配置示例**：

```dts
&i2c2 {
    clock-frequency = <100000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c2>;
    status = "okay";

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

    ov5640: ov5640@3c {
        compatible = "ovti,ov5640";
        reg = <0x3c>;
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_csi1 &pinctrl_camera_clock>;
        clocks = <&clks IMX6UL_CLK_CSI>;
        clock-names = "csi_mclk";
        pwn-gpios = <&gpio_spi 6 1>;
        rst-gpios = <&gpio_spi 5 0>;
        csi_id = <0>;
        mclk = <24000000>;
        mclk_source = <0>;
        status = "disabled";
        port {
            ov5640_ep: endpoint {
                remote-endpoint = <&csi1_ep>;
            };
        };
    };
};
```

**网络配置示例**：

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

### 2.3 关键外设配置

#### 2.3.1 pinctrl配置

pinctrl子系统负责引脚复用和电气特性配置：

```dts
&iomuxc {
    pinctrl-names = "default";

    pinctrl_uart1: uart1grp {
        fsl,pins = <
            MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
            MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
        >;
    };

    pinctrl_enet1: enet1grp {
        fsl,pins = <
            MX6UL_PAD_ENET1_RX_EN__ENET1_RX_EN    0x1b0b0
            MX6UL_PAD_ENET1_RX_ER__ENET1_RX_ER    0x1b0b0
            MX6UL_PAD_ENET1_RX_DATA0__ENET1_RDATA00 0x1b0b0
            MX6UL_PAD_ENET1_RX_DATA1__ENET1_RDATA01 0x1b0b0
            MX6UL_PAD_ENET1_TX_EN__ENET1_TX_EN    0x1b0b0
            MX6UL_PAD_ENET1_TX_DATA0__ENET1_TDATA00 0x1b0b0
            MX6UL_PAD_ENET1_TX_DATA1__ENET1_TDATA01 0x1b0b0
            MX6UL_PAD_ENET1_TX_CLK__ENET1_REF_CLK1 0x4001b031
        >;
    };

    pinctrl_i2c1: i2c1grp {
        fsl,pins = <
            MX6UL_PAD_UART4_TX_DATA__I2C1_SCL 0x4001b8b0
            MX6UL_PAD_UART4_RX_DATA__I2C1_SDA 0x4001b8b0
        >;
    };
};
```

**引脚配置值说明**：

配置值（如`0x1b0b1`）是一个32位整数，包含以下信息：

```
31    23    15    7     0
+-----+-----+-----+------+
| 保留 | 配置 | 速度 | PAD  |
+-----+-----+-----+------+
```

- 低16位：引脚功能选择
- 高16位：电气特性（上拉、驱动强度、转换速率等）

具体值需要参考芯片数据手册。

#### 2.3.2 时钟配置

i.MX6ULL的时钟系统配置：

```dts
&clks {
    assigned-clocks = <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
    assigned-clock-rates = <786432000>;
};

&sai2 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_sai2>;
    assigned-clocks = <&clks IMX6UL_CLK_SAI2_SEL>,
                      <&clks IMX6UL_CLK_SAI2>;
    assigned-clock-parents = <&clks IMX6UL_CLK_PLL4_AUDIO_DIV>;
    assigned-clock-rates = <0>, <12288000>;
    fsl,sai-mclk-direction-output;
    status = "okay";
};
```

**时钟配置要点**：

- `assigned-clocks`：要配置的时钟
- `assigned-clock-rates`：时钟频率（0表示自动选择）
- `assigned-clock-parents`：时钟源选择

#### 2.3.3 电源域配置

```dts
reg_peri_3v3: regulator-peri-3v3 {
    compatible = "regulator-fixed";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_peri_3v3>;
    regulator-name = "VPERI_3V3";
    regulator-min-microvolt = <3300000>;
    regulator-max-microvolt = <3300000>;
    gpio = <&gpio5 2 GPIO_ACTIVE_LOW>;
    regulator-always-on;
};

&fec1 {
    phy-supply = <&reg_peri_3v3>;
    status = "okay";
};
```

---

## 第三部分：常用外设配置

### 3.1 LCD移植

#### 3.1.1 LCD设备树结构

```dts
&lcdif {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lcdif_dat &pinctrl_lcdif_ctrl>;
    display = <&display0>;
    status = "okay";

    display0: display@0 {
        bits-per-pixel = <24>;
        bus-width = <24>;

        display-timings {
            native-mode = <&timing0>;

            timing0: timing0 {
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
        };
    };
};
```

#### 3.1.2 引脚配置

```dts
pinctrl_lcdif_dat: lcdifdatgrp {
    fsl,pins = <
        MX6UL_PAD_LCD_DATA00__LCDIF_DATA00  0x49
        MX6UL_PAD_LCD_DATA01__LCDIF_DATA01  0x49
        MX6UL_PAD_LCD_DATA02__LCDIF_DATA02  0x49
        MX6UL_PAD_LCD_DATA03__LCDIF_DATA03  0x49
        MX6UL_PAD_LCD_DATA04__LCDIF_DATA04  0x49
        MX6UL_PAD_LCD_DATA05__LCDIF_DATA05  0x49
        MX6UL_PAD_LCD_DATA06__LCDIF_DATA06  0x49
        MX6UL_PAD_LCD_DATA07__LCDIF_DATA07  0x49
        MX6UL_PAD_LCD_DATA08__LCDIF_DATA08  0x49
        MX6UL_PAD_LCD_DATA09__LCDIF_DATA09  0x49
        MX6UL_PAD_LCD_DATA10__LCDIF_DATA10  0x49
        MX6UL_PAD_LCD_DATA11__LCDIF_DATA11  0x49
        MX6UL_PAD_LCD_DATA12__LCDIF_DATA12  0x49
        MX6UL_PAD_LCD_DATA13__LCDIF_DATA13  0x49
        MX6UL_PAD_LCD_DATA14__LCDIF_DATA14  0x49
        MX6UL_PAD_LCD_DATA15__LCDIF_DATA15  0x49
        MX6UL_PAD_LCD_DATA16__LCDIF_DATA16  0x49
        MX6UL_PAD_LCD_DATA17__LCDIF_DATA17  0x49
        MX6UL_PAD_LCD_DATA18__LCDIF_DATA18  0x49
        MX6UL_PAD_LCD_DATA19__LCDIF_DATA19  0x49
        MX6UL_PAD_LCD_DATA20__LCDIF_DATA20  0x49
        MX6UL_PAD_LCD_DATA21__LCDIF_DATA21  0x49
        MX6UL_PAD_LCD_DATA22__LCDIF_DATA22  0x49
        MX6UL_PAD_LCD_DATA23__LCDIF_DATA23  0x49
    >;
};

pinctrl_lcdif_ctrl: lcdifctrlgrp {
    fsl,pins = <
        MX6UL_PAD_LCD_CLK__LCDIF_CLK        0x49
        MX6UL_PAD_LCD_ENABLE__LCDIF_ENABLE  0x49
        MX6UL_PAD_LCD_HSYNC__LCDIF_HSYNC    0x49
        MX6UL_PAD_LCD_VSYNC__LCDIF_VSYNC    0x49
    >;
};
```

#### 3.1.3 LCD移植步骤

**1. 获取LCD规格书**

从LCD厂商获取以下参数：
- 分辨率（hactive x vactive）
- 像素时钟（clock-frequency）
- 时序参数（hfront-porch, hback-porch, hsync-len等）
- 接口类型（RGB888/RGB666等）

**2. 修改display-timings**

```dts
timing0: timing0 {
    clock-frequency = <90000000>;     // 根据LCD规格修改
    hactive = <800>;                   // 宽度
    vactive = <480>;                   // 高度
    hfront-porch = <40>;               // 前肩
    hback-porch = <88>;                // 后肩
    hsync-len = <48>;                  // 同步长度
    vback-porch = <32>;
    vfront-porch = <13>;
    vsync-len = <3>;
    hsync-active = <0>;                // 极性
    vsync-active = <0>;
    de-active = <1>;
    pixelclk-active = <0>;
};
```

**3. 计算像素时钟**

像素时钟计算公式：

```
PCLK = (hactive + hfront-porch + hback-porch + hsync-len) *
       (vactive + vfront-porch + vback-porch + vsync-len) *
       刷新率
```

例如，800x480@60Hz：
```
PCLK = (800 + 40 + 88 + 48) * (480 + 13 + 32 + 3) * 60
     = 976 * 528 * 60
     ≈ 30 MHz
```

**4. 调整引脚配置**

根据实际连接的LCD数据线数量调整：

```dts
// 16位色
bus-width = <16>;
bits-per-pixel = <16>;

// 24位色
bus-width = <24>;
bits-per-pixel = <24>;
```

**5. 背光控制**

添加背光PWM配置：

```dts
&pwm1 {
    #pwm-cells = <2>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_pwm1>;
    status = "okay";
};

pinctrl_pwm1: pwm1grp {
    fsl,pins = <
        MX6UL_PAD_GPIO1_IO08__PWM1_OUT 0x110b0
    >;
};
```

### 3.2 网络移植

#### 3.2.1 网络设备树结构

```dts
&fec1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_enet1>;
    phy-mode = "rmii";              // 接口模式：rmii/mii/rgmii
    phy-handle = <&ethphy0>;        // PHY设备引用
    phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;  // PHY复位GPIO
    phy-reset-duration = <200>;     // 复位持续时间（ms）
    phy-reset-post-delay = <200>;   // 复位后延迟（ms）
    phy-supply = <&reg_peri_3v3>;   // PHY电源
    status = "okay";

    mdio {
        #address-cells = <1>;
        #size-cells = <0>;

        ethphy0: ethernet-phy@2 {
            compatible = "ethernet-phy-id0022.1560";  // PHY ID
            reg = <2>;                                  // MDIO地址
            micrel,led-mode = <1>;                      // PHY特定属性
            clocks = <&clks IMX6UL_CLK_ENET_REF>;       // 参考时钟
            clock-names = "rmii-ref";
        };
    };
};
```

#### 3.2.2 PHY ID获取

PHY ID通过MDIO总线读取，格式为`ieee-oui:device-id`：

```bash
# 在Linux系统中读取PHY ID
cat /sys/bus/mdio_bus/devices/phy0/ieee_oui
cat /sys/bus/mdio_bus/devices/phy0/device_id
```

或者使用`mdio-tool`：

```bash
mdio-tool read eth0 0x02 0x02  # 读取PHY ID1
mdio-tool read eth0 0x02 0x03  # 读取PHY ID2
```

#### 3.2.3 网络移植步骤

**1. 确认PHY芯片型号**

查看原理图，确认PHY芯片型号和MDIO地址。

**2. 修改PHY配置**

```dts
ethphy0: ethernet-phy@0 {  // @后面是MDIO地址
    compatible = "ethernet-phy-idaaaa.bbbb";  // 替换为实际PHY ID
    reg = <0>;                                   // 替换为实际MDIO地址
    max-speed = <100>;                           // 最大速度
};
```

**3. 配置PHY复位时序**

```dts
phy-reset-gpios = <&gpioX Y GPIO_ACTIVE_LOW>;  // 替换为实际GPIO
phy-reset-duration = <50>;                      // 根据PHY手册设置
phy-reset-post-delay = <100>;
```

**4. 配置参考时钟**

```dts
// 内部时钟
clocks = <&clks IMX6UL_CLK_ENET_REF>;
clock-names = "rmii-ref";

// 外部时钟（如果使用外部晶振）
// 删除clocks属性，添加：
phy-external-clk;
```

**5. 测试网络**

```bash
# 查看网络接口
ip link show

# 设置IP地址
ip addr add 192.168.1.100/24 dev eth0

# 测试连接
ping 192.168.1.1

# 查看网络统计
ethtool eth0
```

#### 3.2.4 常见PHY芯片配置

**KSZ8081/8091**：

```dts
ethphy0: ethernet-phy@0 {
    compatible = "ethernet-phy-id0022.1560";
    reg = <0>;
    micrel,led-mode = <1>;
};
```

**RTL8201F**：

```dts
ethphy0: ethernet-phy@0 {
    compatible = "ethernet-phy-id0016.8800";
    reg = <0>;
    realtek,led-2-mode = <0x05>;  // LED配置
};
```

**AR8031/8035**：

```dts
ethphy0: ethernet-phy@0 {
    compatible = "ethernet-phy-id004d.d071";
    reg = <0>;
    vddio-supply = <&reg_peri_3v3>;
    vddio: vddio-regulator {
        regulator-name = "vddio";
        regulator-min-microvolt = <1800000>;
        regulator-max-microvolt = <1800000>;
    };
};
```

### 3.3 存储设备（eMMC/SD）

#### 3.3.1 SD卡配置

```dts
&usdhc1 {
    pinctrl-names = "default", "state_100mhz", "state_200mhz";
    pinctrl-0 = <&pinctrl_usdhc1>;
    pinctrl-1 = <&pinctrl_usdhc1_100mhz>;
    pinctrl-2 = <&pinctrl_usdhc1_200mhz>;
    cd-gpios = <&gpio1 19 GPIO_ACTIVE_LOW>;  // 卡检测GPIO
    keep-power-in-suspend;
    wakeup-source;
    vmmc-supply = <&reg_sd1_vmmc>;           // 电源
    status = "okay";
};
```

**SD卡引脚配置**：

```dts
pinctrl_usdhc1: usdhc1grp {
    fsl,pins = <
        MX6UL_PAD_SD1_CMD__USDHC1_CMD     0x17059
        MX6UL_PAD_SD1_CLK__USDHC1_CLK     0x10071
        MX6UL_PAD_SD1_DATA0__USDHC1_DATA0 0x17059
        MX6UL_PAD_SD1_DATA1__USDHC1_DATA1 0x17059
        MX6UL_PAD_SD1_DATA2__USDHC1_DATA2 0x17059
        MX6UL_PAD_SD1_DATA3__USDHC1_DATA3 0x17059
        MX6UL_PAD_UART1_RTS_B__GPIO1_IO19  0x17059  // CD引脚
        MX6UL_PAD_GPIO1_IO05__USDHC1_VSELECT 0x17059  // 电压选择
    >;
};
```

#### 3.3.2 eMMC配置

```dts
&usdhc2 {
    pinctrl-names = "default", "state_100mhz", "state_200mhz";
    pinctrl-0 = <&pinctrl_usdhc2_8bit>;
    pinctrl-1 = <&pinctrl_usdhc2_8bit_100mhz>;
    pinctrl-2 = <&pinctrl_usdhc2_8bit_200mhz>;
    bus-width = <8>;                    // 8位数据线
    non-removable;                      // 不可移除
    keep-power-in-suspend;
    wakeup-source;
    status = "okay";
};
```

**eMMC引脚配置**：

```dts
pinctrl_usdhc2_8bit: usdhc2grp_8bit {
    fsl,pins = <
        MX6UL_PAD_NAND_RE_B__USDHC2_CLK     0x10069
        MX6UL_PAD_NAND_WE_B__USDHC2_CMD     0x17059
        MX6UL_PAD_NAND_DATA00__USDHC2_DATA0 0x17059
        MX6UL_PAD_NAND_DATA01__USDHC2_DATA1 0x17059
        MX6UL_PAD_NAND_DATA02__USDHC2_DATA2 0x17059
        MX6UL_PAD_NAND_DATA03__USDHC2_DATA3 0x17059
        MX6UL_PAD_NAND_DATA04__USDHC2_DATA4 0x17059
        MX6UL_PAD_NAND_DATA05__USDHC2_DATA5 0x17059
        MX6UL_PAD_NAND_DATA06__USDHC2_DATA6 0x17059
        MX6UL_PAD_NAND_DATA07__USDHC2_DATA7 0x17059
    >;
};
```

#### 3.3.3 存储设备移植要点

**1. 确定数据线宽度**

- SD卡：通常4位
- eMMC：通常8位

**2. 配置卡检测**

```dts
// 有CD引脚
cd-gpios = <&gpioX Y GPIO_ACTIVE_LOW>;

// 无CD引脚（始终认为卡存在）
broken-cd;
no-1-8-v;
```

**3. 配置电源**

```dts
// 使用GPIO控制电源
reg_sd1_vmmc: regulator-sd1-vmmc {
    compatible = "regulator-fixed";
    regulator-name = "VSD_3V3";
    regulator-min-microvolt = <3300000>;
    regulator-max-microvolt = <3300000>;
    gpio = <&gpio1 9 GPIO_ACTIVE_HIGH>;
    enable-active-high;
};

&usdhc1 {
    vmmc-supply = <&reg_sd1_vmmc>;
};
```

**4. 调试存储设备**

```bash
# 查看设备
ls /sys/block/mmcblk*

# 查看详细信息
cat /sys/class/mmc_host/mmc0/mmc0:0001/serial

# 性能测试
dd if=/dev/zero of=/mnt/test bs=1M count=100 oflag=direct
dd if=/mnt/test of=/dev/null bs=1M count=100 iflag=direct
```

### 3.4 GPIO配置

#### 3.4.1 GPIO基础配置

```dts
// 定义LED GPIO
led {
    compatible = "gpio-leds";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_led>;

    status-led {
        label = "status";
        gpios = <&gpio1 3 GPIO_ACTIVE_HIGH>;
        default-state = "on";
    };
};

// 引脚配置
pinctrl_led: ledgrp {
    fsl,pins = <
        MX6UL_PAD_GPIO1_IO03__GPIO1_IO03 0x17059
    >;
};
```

#### 3.4.2 GPIO按键配置

```dts
gpio-keys {
    compatible = "gpio-keys";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_gpio_keys>;

    button-user {
        label = "User Button";
        gpios = <&gpio1 5 GPIO_ACTIVE_LOW>;
        linux,code = <KEY_POWER>;
        wakeup-source;
    };
};

pinctrl_gpio_keys: gpio_keysgrp {
    fsl,pins = <
        MX6UL_PAD_GPIO1_IO05__GPIO1_IO05 0x80000000
    >;
};
```

#### 3.4.3 GPIO调试

```bash
# 查看GPIO信息
cat /sys/kernel/debug/gpio

# 导出GPIO（用户空间控制）
echo 4 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio4/direction
echo 1 > /sys/class/gpio/gpio4/value

# 读取GPIO值
cat /sys/class/gpio/gpio4/value

# 设置GPIO边沿触发
echo rising > /sys/class/gpio/gpio4/edge
```

### 3.5 I2C设备

#### 3.5.1 I2C基础配置

```dts
&i2c1 {
    clock-frequency = <100000>;              // 总线频率：100kHz/400kHz
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c1>;
    status = "okay";

    // I2C设备示例
    eeprom@50 {
        compatible = "atmel,24c256";
        reg = <0x50>;
        pagesize = <64>;
    };

    sensor@48 {
        compatible = "ti,tmp105";
        reg = <0x48>;
    };
};
```

#### 3.5.2 I2C引脚配置

```dts
pinctrl_i2c1: i2c1grp {
    fsl,pins = <
        MX6UL_PAD_UART4_TX_DATA__I2C1_SCL 0x4001b8b0
        MX6UL_PAD_UART4_RX_DATA__I2C1_SDA 0x4001b8b0
    >;
};
```

**电气特性值说明**：

- `0x4001b8b0`：标准I2C配置（100kHz）
- 高速模式（400kHz）：调整上拉和驱动强度

#### 3.5.3 I2C设备移植步骤

**1. 扫描I2C总线**

```bash
# 使用i2c-tool扫描
i2cdetect -y 0  # 扫描I2C bus 0
i2cdetect -y 1  # 扫描I2C bus 1
```

**2. 读取设备信息**

```bash
# 读取设备寄存器
i2cdump -y 1 0x50

# 读取单个寄存器
i2cget -y 1 0x50 0x00

# 写入寄存器
i2cset -y 1 0x50 0x00 0x12
```

**3. 添加设备到设备树**

```dts
&i2c1 {
    status = "okay";

    your-device@XX {
        compatible = "vendor,model";
        reg = <0xXX>;  // I2C地址
        // 其他属性...
    };
};
```

### 3.6 SPI设备

#### 3.6.1 硬件SPI配置

```dts
&ecspi1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_ecspi1>;
    cs-gpios = <&gpio4 26 GPIO_ACTIVE_LOW>;
    status = "okay";

    spidev0: spi@0 {
        compatible = "rohm,dh2228fv";
        reg = <0>;
        spi-max-frequency = <5000000>;
    };
};

pinctrl_ecspi1: ecspi1grp {
    fsl,pins = <
        MX6UL_PAD_CSI_DATA07__ECSPI1_MISO 0x100b1
        MX6UL_PAD_CSI_DATA06__ECSPI1_MOSI 0x100b1
        MX6UL_PAD_CSI_DATA04__ECSPI1_SCLK 0x100b1
        MX6UL_PAD_CSI_DATA05__GPIO4_IO26  0x100b1  // CS
    >;
};
```

#### 3.6.2 GPIO模拟SPI

```dts
spi-4 {
    compatible = "spi-gpio";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_spi4>;
    status = "okay";
    gpio-sck = <&gpio5 11 0>;
    gpio-mosi = <&gpio5 10 0>;
    num-chipselects = <1>;
    #address-cells = <1>;
    #size-cells = <0>;

    gpio_spi: gpio@0 {
        compatible = "fairchild,74hc595";
        gpio-controller;
        #gpio-cells = <2>;
        reg = <0>;
        registers-number = <1>;
        registers-default = /bits/ 8 <0x57>;
        spi-max-frequency = <100000>;
    };
};

pinctrl_spi4: spi4grp {
    fsl,pins = <
        MX6UL_PAD_BOOT_MODE0__GPIO5_IO10 0x70a1
        MX6UL_PAD_BOOT_MODE1__GPIO5_IO11 0x70a1
    >;
};
```

### 3.7 UART配置

#### 3.7.1 UART基础配置

```dts
&uart1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart1>;
    status = "okay";
};

&uart2 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart2>;
    uart-has-rtscts;  // 使用硬件流控
    status = "okay";
};
```

#### 3.7.2 UART引脚配置

```dts
pinctrl_uart1: uart1grp {
    fsl,pins = <
        MX6UL_PAD_UART1_TX_DATA__UART1_DCE_TX 0x1b0b1
        MX6UL_PAD_UART1_RX_DATA__UART1_DCE_RX 0x1b0b1
    >;
};

pinctrl_uart2: uart2grp {
    fsl,pins = <
        MX6UL_PAD_UART2_TX_DATA__UART2_DCE_TX 0x1b0b1
        MX6UL_PAD_UART2_RX_DATA__UART2_DCE_RX 0x1b0b1
        MX6UL_PAD_UART3_RX_DATA__UART2_DCE_RTS 0x1b0b1
        MX6UL_PAD_UART3_TX_DATA__UART2_DCE_CTS 0x1b0b1
    >;
};
```

#### 3.7.3 UART调试

```bash
# 查看UART设备
ls -l /dev/tty*

# 使用minicom测试
minicom -D /dev/ttySTM0 -b 115200

# 使用echo测试
echo "test" > /dev/ttySTM0

# 查看UART配置
stty -F /dev/ttySTM0 -a
```

---

## 第四部分：自定义板卡移植步骤

### 4.1 从Alpha板开始

移植新板卡的最佳实践是从Alpha板开始，逐步修改。这是因为：

1. Alpha板已经过验证，配置正确
2. 可以减少遗漏重要配置
3. 便于对比差异

#### 4.1.1 创建新板卡目录

```bash
# 在U-Boot设备树目录创建新板卡
cd third_party/uboot-imx/arch/arm/dts/
cp imx6ull-aes.dts imx6ull-myboard.dts
cp imx6ull-aes.dtsi imx6ull-myboard.dtsi

# 在Linux设备树目录创建新板卡
cd third_party/linux_mainline/arch/arm/boot/dts/nxp/imx/
cp imx6ull-aes.dts imx6ull-myboard.dts
cp imx6ull-aes.dtsi imx6ull-myboard.dtsi
```

#### 4.1.2 修改基本配置

```dts
// 修改model和compatible
/ {
    model = "MyCompany MyBoard i.MX6ULL";
    compatible = "mycompany,myboard", "fsl,imx6ull";
};

// 修改memory配置（如果内存大小不同）
memory@80000000 {
    device_type = "memory";
    reg = <0x80000000 0x10000000>;  // 256MB
};
```

### 4.2 修改设备树

#### 4.2.1 修改外设配置清单

准备一份外设对比表：

| 外设 | Alpha板 | 新板卡 | 修改内容 |
|------|---------|--------|----------|
| LCD | 1024x600 | 800x480 | 修改display-timings |
| 网络 | KSZ8091 | RTL8201F | 修改PHY配置 |
| 存储 | eMMC | SD | 删除usdhc2配置 |
| I2C | WM8960 | 无 | 删除codec节点 |

#### 4.2.2 分步修改

**步骤1：禁用所有外设**

```dts
// 先禁用所有外设，逐个启用
&fec1 {
    status = "disabled";
};

&fec2 {
    status = "disabled";
};

&lcdif {
    status = "disabled";
};

&i2c1 {
    status = "disabled";
};

&i2c2 {
    status = "disabled";
};
```

**步骤2：启用并配置基础外设**

先配置UART（调试用），再配置其他外设：

```dts
&uart1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart1>;
    status = "okay";
};
```

**步骤3：逐个添加外设**

每次只添加一个外设，测试通过后再添加下一个：

```dts
// 1. 添加网络
&fec1 {
    status = "okay";
    // 测试通过
};

// 2. 添加LCD
&lcdif {
    status = "okay";
    // 测试通过
};

// 3. 添加I2C
&i2c1 {
    status = "okay";
    // 测试通过
};
```

#### 4.2.3 引脚对照表

创建引脚对照表，方便查找和修改：

| 功能 | Alpha板引脚 | 新板卡引脚 | 宏定义 |
|------|-------------|------------|--------|
| UART1_TX | UART1_TX_DATA | UART1_TX_DATA | MX6UL_PAD_UART1_TX_DATA |
| UART1_RX | UART1_RX_DATA | UART1_RX_DATA | MX6UL_PAD_UART1_RX_DATA |
| ENET1_TX | ENET1_TX_DATA0 | GPIO1_IOxx | MX6UL_PAD_GPIO1_IOxx |

### 4.3 验证步骤

#### 4.3.1 编译验证

```bash
# 编译U-Boot设备树
cd third_party/uboot-imx
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx6ull-myboard.dtb

# 编译Linux设备树
cd third_party/linux_mainline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs
```

#### 4.3.2 语法检查

```bash
# 检查语法错误
dtc -I dts -O dtb -o /dev/null imx6ull-myboard.dts

# 显示警告
dtc -I dts -O dtb -o output.dtb imx6ull-myboard.dts -W
```

#### 4.3.3 功能测试

**1. U-Boot阶段测试**

```bash
# 在U-Boot命令行测试
# 查看设备树
fdt addr $fdt_addr_r
fdt print /

# 测试LCD
bmp display

# 测试网络
dhcp
tftpboot
```

**2. Linux阶段测试**

```bash
# 查看设备树
cat /sys/firmware/devicetree/base/model
cat /proc/device-tree/compatible

# 查看设备
ls /sys/devices/platform/
ls /sys/class/net/

# 测试网络
ip link set eth0 up
udhcpc -i eth0

# 测试LCD
cat /dev/urandom > /dev/fb0

# 测试I2C
i2cdetect -y 0
```

#### 4.3.4 日志分析

```bash
# 查看内核启动日志
dmesg | less

# 过滤设备树相关日志
dmesg | grep of:
dmesg | grep fdt

# 查看特定外设日志
dmesg | grep fec
dmesg | grep lcdif
```

### 4.4 常见问题

#### 4.4.1 编译错误

**问题：找不到包含文件**

```
imx6ull-myboard.dts:10: could not find include file
```

**解决**：检查包含路径，确保`-i`参数正确：

```bash
dtc -I dts -O dtb -o output.dtb input.dts \
    -i arch/arm/boot/dts \
    -i arch/arm/boot/dts/nxp/imx
```

**问题：语法错误**

```
imx6ull-myboard.dts:100: syntax error
```

**解决**：检查括号匹配、分号、引号等。

#### 4.4.2 启动失败

**问题：内核启动失败，无输出**

**排查步骤**：

1. 检查UART配置（console）
2. 检查chosen节点
3. 检查memory配置

```dts
chosen {
    stdout-path = &uart1;  // 确保正确
};
```

**问题：内核恐慌**

```
Kernel panic - not syncing: No working init found.
```

**解决**：检查根文件系统配置。

#### 4.4.3 外设不工作

**问题：网络不工作**

**排查步骤**：

```bash
# 1. 检查PHY是否被识别
cat /sys/bus/mdio_bus/devices/

# 2. 检查网络接口
ip link show

# 3. 查看网络驱动日志
dmesg | grep fec

# 4. 测试PHY通信
mdio-tool read eth0 0x00 0x02
```

**问题：LCD不显示**

**排查步骤**：

```bash
# 1. 检查帧缓冲设备
ls /dev/fb*

# 2. 查看LCD驱动日志
dmesg | grep lcdif

# 3. 测试显示
cat /dev/urandom > /dev/fb0

# 4. 检查display-timings
dmesg | grep -i timing
```

**问题：I2C设备不响应**

**排查步骤**：

```bash
# 1. 扫描I2C总线
i2cdetect -y 0

# 2. 检查I2C驱动
dmesg | grep i2c

# 3. 测试I2C通信
i2cget -y 0 0x50 0x00
```

#### 4.4.4 引脚冲突

**问题：多个外设使用同一引脚**

**解决**：使用`pinctrl-single`或重新分配引脚：

```dts
// 使用不同引脚
pinctrl_uart2: uart2grp {
    fsl,pins = <
        // 修改为其他可用引脚
        MX6UL_PAD_GPIO1_IO06__UART2_DCE_TX 0x1b0b1
        MX6UL_PAD_GPIO1_IO07__UART2_DCE_RX 0x1b0b1
    >;
};
```

---

## 第五部分：设备树调试

### 5.1 语法检查

#### 5.1.1 编译时检查

```bash
# 基本语法检查
dtc -I dts -O dtb -o output.dtb input.dts

# 详细检查（显示所有信息）
dtc -I dts -O dtb -o output.dtb input.dts -f

# 检查但不输出
dtc -I dts -O dtb -o /dev/null input.dts

# 检查包含文件
dtc -I dts -O dtb -o output.dtb input.dts \
    -i arch/arm/boot/dts \
    -I dts -O dtb
```

#### 5.1.2 常见语法错误

**错误1：缺少分号**

```dts
// 错误
&uart1 {
    status = "okay"
}

// 正确
&uart1 {
    status = "okay";
};
```

**错误2：括号不匹配**

```dts
// 错误
&uart1 {
    status = "okay";
// 缺少闭合};

// 正确
&uart1 {
    status = "okay";
};
```

**错误3：引用不存在**

```dts
// 错误
pinctrl-0 = <&pinctrl_nonexistent>;

// 确保引用的节点已定义
```

### 5.2 编译验证

#### 5.2.1 U-Boot设备树编译

```bash
# 方法1：使用U-Boot Makefile
cd third_party/uboot-imx
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    imx6ull-myboard.dtb

# 方法2：直接使用dtc
dtc -I dts -O dtb \
    -i arch/arm/dts \
    -o imx6ull-myboard.dtb \
    arch/arm/dts/imx6ull-myboard.dts
```

#### 5.2.2 Linux设备树编译

```bash
# 方法1：使用Linux Makefile
cd third_party/linux_mainline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs

# 方法2：直接编译单个文件
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    nxp/imx/imx6ull-myboard.dtb
```

#### 5.2.3 验证编译结果

```bash
# 检查DTB文件
file imx6ull-myboard.dtb

# 应该输出：
# imx6ull-myboard.dtb: Device Tree Blob version 17

# 反编译检查
dtc -I dtb -O dts -o output.dts imx6ull-myboard.dts
less output.dts
```

### 5.3 运行时调试

#### 5.3.1 查看运行时设备树

```bash
# 方法1：通过sysfs
ls /sys/firmware/devicetree/base/

# 方法2：通过procfs
ls /proc/device-tree/

# 查看特定节点
cat /sys/firmware/devicetree/base/model
cat /proc/device-tree/compatible
```

#### 5.3.2 设备树反编译

```bash
# 从运行中的系统获取DTB
cat /sys/firmware/devicetree/base/ > /tmp/running.dtb

# 反编译
dtc -I dtb -O dts -o /tmp/running.dts /tmp/running.dtb

# 对比原始DTS和运行时DTS
diff imx6ull-myboard.dts /tmp/running.dts
```

#### 5.3.3 设备匹配调试

```bash
# 查看设备是否创建
ls /sys/devices/platform/

# 查看驱动是否加载
lsmod | grep driver_name

# 查看驱动绑定情况
ls -l /sys/bus/platform/devices/*/driver

# 查看设备的modalias
cat /sys/devices/platform/serial@02020000/modalias
```

#### 5.3.4 日志分析

```bash
# 设备树相关日志
dmesg | grep of:
dmesg | grep fdt
dmesg | grep devicetree

# 特定设备日志
dmesg | grep fec
dmesg | grep uart
dmesg | grep i2c

# 启用详细日志
echo 0x8 > /sys/module/driver/parameters/debug
dmesg | grep -v "^[[:space:]]*$" | tail -100
```

#### 5.3.5 动态设备树修改（Linux）

```bash
# 挂载configfs（用于设备树叠加）
mount -t configfs none /sys/kernel/config/

# 创建叠加目录
mkdir /sys/kernel/config/device-tree/overlays/myoverlay

# 加载叠加DTB
cat myoverlay.dtbo > /sys/kernel/config/device-tree/overlays/myoverlay/dtbo

# 查看叠加
ls /sys/kernel/config/device-tree/overlays/

# 删除叠加
rmdir /sys/kernel/config/device-tree/overlays/myoverlay
```

#### 5.3.6 设备树验证工具

```bash
# 检查设备树完整性
dtc -I dtb -O dts /sys/firmware/devicetree/base/ | less

# 使用fdtvalidate（如果可用）
fdtvalidate input.dts

# 检查compatible字符串
grep -r "compatible" /sys/firmware/devicetree/base/
```

#### 5.3.7 性能分析

```bash
# 设备树解析时间
dmesg | grep "Device Tree"

# 设备probe时间
dmesg | grep "probe"

# 总体启动时间分析
systemd-analyze blame
```

---

## 附录A：参考资源

### 设备树规范
- [Devicetree Specification](https://www.devicetree.org/) - 官方设备树规范
- [Linux Device Tree](https://www.kernel.org/doc/Documentation/devicetree/) - Linux内核设备树文档

### i.MX6ULL资源
- [i.MX6ULL Reference Manual](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf) - NXP官方参考手册
- [i.MX6ULL Datasheet](https://www.nxp.com/docs/en/data-sheet/IMX6ULLCEC.pdf) - 芯片数据手册

### 开发工具
- [Device Tree Compiler](https://github.com/dgibson/dtc) - DTC工具源码
- [dtc](https://elinux.org/Device_Tree_Compiler) - ELinux上的DTC介绍

### 社区资源
- [Linux Kernel Device Tree](https://www.kernel.org/doc/Documentation/devicetree/bindings/) - 设备树绑定文档
- [U-Boot Device Tree](https://www.denx.de/wiki/U-Boot/DeviceTree) - U-Boot设备树文档

---

## 附录B：快速参考

### B.1 常用DTC命令

```bash
# 编译
dtc -I dts -O dtb -o output.dtb input.dts

# 反编译
dtc -I dtb -O dts -o output.dts input.dtb

# 语法检查
dtc -I dts -O dtb -o /dev/null input.dts

# 包含依赖
dtc -I dts -O dtb -o output.dtb input.dts -i include_path
```

### B.2 常用宏定义

```dts
// GPIO_ACTIVE flags
GPIO_ACTIVE_HIGH = 0
GPIO_ACTIVE_LOW  = 1

// 常用compatible
"fsl,imx6ull-uart"
"fsl,imx6ul-i2c"
"fsl,imx6ull-fec"
"simple-bus"
"gpio-leds"
"gpio-keys"
"fixed-regulator"
```

### B.3 常用属性速查

| 属性 | 用途 | 示例 |
|------|------|------|
| compatible | 设备匹配 | "fsl,imx6ull-uart" |
| reg | 地址范围 | <0x02020000 0x4000> |
| status | 设备状态 | "okay" / "disabled" |
| #address-cells | 地址cell数 | <1> |
| #size-cells | 大小cell数 | <1> |
| interrupts | 中断号 | <26 2 0> |
| gpios | GPIO配置 | <&gpio1 3 GPIO_ACTIVE_LOW> |
| clocks | 时钟引用 | <&clks IMX6UL_CLK_UART1_IPG> |

### B.4 调试命令速查

```bash
# 查看设备树
cat /sys/firmware/devicetree/base/model
cat /proc/device-tree/compatible

# 查看设备
ls /sys/devices/platform/
ls /sys/class/net/
ls /dev/fb*

# I2C调试
i2cdetect -y 0
i2cget -y 0 0x50 0x00

# SPI调试
ls /dev/spidev*
spi-config

# 网络调试
ip link show
ethtool eth0

# 日志查看
dmesg | grep device
dmesg | grep fec
```

---

**文档版本**：v1.0
**最后更新**：2026-03-15
**维护者**：IMX-Forge Project
