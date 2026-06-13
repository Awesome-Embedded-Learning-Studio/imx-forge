---
title: 双网口移植
---

# 双网口移植：FEC + KSZ8081/8041 以太网配置

## 前言：网络是嵌入式开发的命脉

说实话，开发嵌入式板子，串口能用来调试，但网络才是日常工作的主力。你用 NFS 挂载根文件系统、用 SSH 登录、用 wget 下载文件，都离不开网络。正点原子 i.MX6ULL 开发板有两个网口，这也是它的一大卖点。

这篇文章讲的是如何配置双网口：i.MX6ULL 有两个 FEC（Fast Ethernet Controller）控制器，每个外接一个 KSZ8081 PHY 芯片。主线内核的 FEC 驱动已经比较成熟了，我们主要是配置设备树和 PHY。

## 第一步——了解 i.MX6ULL 的以太网架构

i.MX6ULL 有两个独立的 FEC 控制器：

| 控制器 | 寄存器地址 | PHY 接口 | PHY 芯片 |
|--------|------------|----------|----------|
| FEC1 | 0x2188000 | RMII | KSZ8081 (地址 0x02) |
| FEC2 | 0x20b4000 | RMII | KSZ8081 (地址 0x01) |

两个控制器都支持 RMII（Reduced Media Independent Interface）接口，比 MII 少一半的引脚，适合嵌入式板子。

### RMII 接口信号

RMII 接口只需要 7 根数据线（加上时钟和电源）：

- TXD1, TXD0：发送数据
- RXD1, RXD0：接收数据
- TX_EN：发送使能
- CRS_DV：载波侦听/数据有效
- REF_CLK：参考时钟（50MHz，由 PHY 提供）

## 第二步——配置 FEC1 节点

FEC1 是第一个以太网控制器，设备树配置如下：

```dts
&fec1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_enet1 &pinctrl_enet1_reset>;
    phy-mode = "rmii";
    phy-handle = <&ethphy0>;
    phy-supply = <&reg_peri_3v3>;
    status = "okay";
};
```

### 关键属性说明

| 属性 | 说明 |
|------|------|
| phy-mode | 接口模式，这里用 "rmii" |
| phy-handle | PHY 节点的 phandle，指向 mdio 总线下的 ethphy0 |
| phy-supply | PHY 供电 regulator |

### pinctrl 配置

FEC1 的引脚配置包括 RMII 数据线和 PHY 复位引脚：

```dts
&iomuxc {
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

    pinctrl_enet1_reset: enet1resetgrp {
        fsl,pins = <
            MX6UL_PAD_SNVS_TAMPER7__GPIO5_IO07    0x10B0
        >;
    };
};
```

注意 `ENET1_REF_CLK1` 的配置值是 `0x4001b031`，这个配置比较特殊：
- `0x40000000`：表示这个引脚配置了 50MHz 的输入时钟（由 PHY 提供）
- 其他位是标准的引脚配置

## 第三步——配置 FEC2 节点

FEC2 的配置类似，但 MDIO 总线通常挂在 FEC2 下面：

```dts
&fec2 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_enet2 &pinctrl_enet2_reset>;
    phy-mode = "rmii";
    phy-handle = <&ethphy1>;
    phy-supply = <&reg_peri_3v3>;
    status = "okay";

    /* MDIO 总线 */
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

### MDIO 总线

MDIO（Management Data Input/Output）总线用于访问 PHY 芯片的寄存器。它是一个两线总线（MDC 和 MDIO），类似 I2C。

- `ethphy0`：FEC1 对应的 PHY，地址是 2
- `ethphy1`：FEC2 对应的 PHY，地址是 1

PHY 地址由硬件上的引脚配置决定，不能随便改。

### KSZ8081 特定配置

KSZ8081 是 Micrel 公司（现在被 Microchip 收购了）的 PHY 芯片，驱动需要一些特定配置：

```dts
ethphy0: ethernet-phy@2 {
    compatible = "ethernet-phy-id0022.1560";  /* OUI + 型号 */
    reg = <2>;
    micrel,led-mode = <1>;                    /* LED 模式 */
    clocks = <&clks IMX6UL_CLK_ENET_REF>;
    clock-names = "rmii-ref";
};
```

- `ethernet-phy-id0022.1560`：兼容字符串，`0022.1560` 是 OUI（厂商 ID）+ 型号
- `micrel,led-mode = <1>`：LED 指示模式，1 表示某些 LED 行为
- `clocks`：RMII 参考时钟，由 PHY 提供

### pinctrl 配置

FEC2 的引脚配置：

```dts
&iomuxc {
    pinctrl_enet2: enet2grp {
        fsl,pins = <
            MX6UL_PAD_GPIO1_IO07__ENET2_MDC     0x1b0b0
            MX6UL_PAD_GPIO1_IO06__ENET2_MDIO    0x1b0b0
            MX6UL_PAD_ENET2_RX_EN__ENET2_RX_EN  0x1b0b0
            MX6UL_PAD_ENET2_RX_ER__ENET2_RX_ER  0x1b0b0
            MX6UL_PAD_ENET2_RX_DATA0__ENET2_RDATA00 0x1b0b0
            MX6UL_PAD_ENET2_RX_DATA1__ENET2_RDATA01 0x1b0b0
            MX6UL_PAD_ENET2_TX_EN__ENET2_TX_EN  0x1b0b0
            MX6UL_PAD_ENET2_TX_DATA0__ENET2_TDATA00 0x1b0b0
            MX6UL_PAD_ENET2_TX_DATA1__ENET2_TDATA01 0x1b0b0
            MX6UL_PAD_ENET2_TX_CLK__ENET2_REF_CLK2 0x4001b031
        >;
    };

    pinctrl_enet2_reset: enet2resetgrp {
        fsl,pins = <
            MX6UL_PAD_SNVS_TAMPER8__GPIO5_IO08    0x10B0
        >;
    };
};
```

## 第四步——配置 PHY 复位引脚

PHY 芯片通常有一个复位引脚（RST#），低电平有效。正点原子板子用 GPIO 控制这个引脚。

### 方法一：使用 GPIO hog

如果复位引脚只需要在启动时复位一次，不需要动态控制，可以用 GPIO hog：

```dts
&gpio_spi {
    eth0-phy-hog {
        gpio-hog;
        gpios = <1 GPIO_ACTIVE_HIGH>;
        output-high;
        line-name = "eth0-phy";
    };

    eth1-phy-hog {
        gpio-hog;
        gpios = <2 GPIO_ACTIVE_HIGH>;
        output-high;
        line-name = "eth1-phy";
    };
};
```

GPIO hog 是一种在设备树里直接配置 GPIO 的方式，不需要驱动代码。

### 方法二：使用 phy-reset-gpios

另一种方法是在 FEC 节点里指定 PHY 复位引脚：

```dts
&fec1 {
    phy-mode = "rmii";
    phy-handle = <&ethphy0>;
    phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
    phy-reset-duration = <26>;
};
```

但这种方法在主线内核里可能不支持，需要确认驱动版本。

## 第五步——配置 regulator

PHY 芯片需要 3.3V 供电：

```dts
/ {
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
};
```

`regulator-always-on` 表示这个 regulator 始终开启，不能被关闭。

## 第六步——验证网络驱动加载

启动后，检查 dmesg 里的网络相关日志：

```bash
dmesg | grep -E "fec|net|phy|eth"
```

你应该看到类似这样的输出：

```
[    1.234567] fec 2188000.ethernet: registered PHY driver [Micrel KSZ8081] (mii_bus:phy_addr=2188000.ethernet:02, irq=POLL)
[    1.345678] fec 2188000.ethernet eth0: Link is Up - 100Mbps/Full - flow control off
[    2.456789] fec 20b4000.ethernet: registered PHY driver [Micrel KSZ8081] (mii_bus:phy_addr=20b4000.ethernet:01, irq=POLL)
[    2.567890] fec 20b4000.ethernet eth1: Link is Up - 100Mbps/Full - flow control off
```

关键是 `Link is Up - 100Mbps/Full`，说明 PHY 和链路协商成功。

### 检查网络接口

```bash
ip link show
# 应该看到 eth0 和 eth1

ifconfig -a
# 或
ip addr show
```

## 第七步——网络功能测试

### 方法一：ping 测试

```bash
# 假设你的电脑 IP 是 192.168.1.100
ping -c 4 192.168.1.100

# 测试两个网口
ping -I eth0 -c 4 192.168.1.100
ping -I eth1 -c 4 192.168.1.100
```

### 方法二：iperf 测试

如果你的电脑也运行了 iperf 服务器：

```bash
# 板子作为客户端
iperf3 -c 192.168.1.100 -i 1 -t 10
```

这会测试网络吞吐量，100Mbps 的理论值是 12.5MB/s，实际能达到 10-11MB/s 就不错了。

### 方法三：ethtool 检查

```bash
ethtool eth0
ethtool eth1
```

你应该看到 PHY 的详细信息：速度、双工模式、链接状态等。

## 常见问题排查

### 问题一：网络接口没有出现

检查以下几点：

1. FEC 驱动是否编译进内核：
```bash
zcat /proc/config.gz | grep FEC
# 应该看到 CONFIG_FEC=y
```

2. PHY 驱动是否开启：
```bash
zcat /proc/config.gz | grep MICREL
# 应该看到 CONFIG_MICREL_PHY=y
```

3. 设备树里的 status 是否为 "okay"

### 问题二：链路不起来（Link is Down）

这种情况通常是硬件问题：

1. 检查网线是否插好
2. 检查 PHY 供电是否正常（用万用表测 VDD 引脚）
3. 检查 PHY 复位是否正确（复位引脚应该是高电平）
4. 检查 RMII 时钟是否正常（示波器测量 REF_CLK）

### 问题三：能 ping 通但速度很慢

这种情况可能是：

1. 中断亲和性：CPU 处理网络中断的速度不够
2. DMA 配置：FEC 的 DMA 缓冲区设置
3. 驱动配置：检查 FEC 驱动的配置选项

### 问题四：两个网口只有一个能用

检查 MDIO 总线配置。两个 PHY 共享一个 MDIO 总线，如果地址配置冲突，只有一个能工作。

确认 PHY 地址：
- ethphy0 应该是地址 2
- ethphy1 应该是地址 1

这些地址由 PHY 芯片的硬件引脚决定，不能在软件里改。

## 下一章预告

到这里，三大外设（显示、触摸、网络）都移植完了。你已经有一个基本可用的图形界面开发环境了。

下一篇文章，我们会讲调试技巧：

- dmesg 日志分析方法
- 设备树验证技巧
- DRM 调试接口
- 内核配置检查方法
- 常用调试命令速查

调试是嵌入式开发的必备技能，掌握了这些方法，遇到问题就能快速定位。我们下一章见。

---

**参考命令速查**

```bash
# 检查网络驱动
dmesg | grep -E "fec|net|phy|eth"

# 检查网络接口
ip link show
ifconfig -a

# 测试网络
ping -c 4 192.168.1.100
iperf3 -c 192.168.1.100 -i 1 -t 10

# 检查 PHY 状态
ethtool eth0
cat /sys/class/net/eth0/operstate

# 读写 PHY 寄存器
cat /sys/bus/mdio_bus/devices/2188000.ethernet:02/phy_id
```

**延伸阅读**

- [FEC Driver Documentation](https://www.kernel.org/doc/html/latest/networking/driver/freescale/fec.html) - FEC 驱动文档
- [PHY Driver Documentation](https://www.kernel.org/doc/html/latest/networking/phy.html) - PHY 驱动文档
- [KSZ8081 Datasheet](https://www.microchip.com/en-us/product/KSZ8081RNA) - KSZ8081 数据手册
