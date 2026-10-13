# 触摸屏移植：GT9147/Goodix 驱动配置

## 前言：有了显示，还需要输入

说实话，LCD 亮了那一刻，笔者也挺激动。但紧接着您就会发现：鼠标点不了、触摸没反应，屏幕就像一个漂亮的画板，只能看不能摸。这时候才意识到，显示只是图形系统的一半，另一半是输入。

这篇文章讲的是正点原子 i.MX6ULL 开发板上的 GT9147 触摸屏驱动移植。Goodix GT9 系列是国产触摸芯片里比较常见的一款，主线内核已经有支持了，咱们主要的工作是设备树配置和 GPIO 冲突解决。

## 第一步——了解 GT9147 硬件连接

GT9147 是 I2C 接口的电容触摸芯片，咱们先看它在正点原子板子上的连接，大致是这样：

| 信号 | 引脚 | 功能 |
|------|------|------|
| SCL | UART5_TX (I2C2_SCL) | I2C 时钟 |
| SDA | UART5_RX (I2C2_SDA) | I2C 数据 |
| INT | GPIO1_IO09 | 触摸中断（低电平有效） |
| RST | GPIO1_IO05 | 复位（低电平有效） |
| VDD | 3.3V | 电源 |
| AVDD | 2.8V | 模拟电源 |

I2C 地址这件事，本章得先把双轨口径立起来，后面所有的验证输出都跟它有关。真实的正点原子板子上，这颗芯片实测挂在 0x14（7 位地址，笔者拿 i2cdetect 在 I2C2 上扫出来的）；有些资料写 0xba，那是把读写位也算进去的 8 位形式，对应 7 位的 0x28，内核和设备树里只认 7 位地址。QEMU 那边是另一条轨：gt911 模型把地址硬编码在 0x5d，改不了，来龙去脉 07 篇的战史二已经讲过，修复排在 QEMU 的 gt911 模型支持改地址之后。所以您在 QEMU 里 i2cdetect 看到 1-005d、在真板上看到 1-0014，两个都是对的，没有谁写错；设备树也各写各的，本章的板级 dts 伺候真板，写 0x14，08 篇 QEMU 验收那套写 0x5d。

## 第二步——配置 I2C 总线

GT9147 挂在 I2C2 总线上，咱们首先确认 I2C2 节点配置：

```dts
&i2c2 {
    clock-frequency = <100000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c2>;
    status = "okay";

    /* GT9147 触摸屏节点 */
    gt9147: gt9147@14 {
        compatible = "goodix,gt9147", "goodix,gt9xx";
        /* 真板实测地址 0x14；QEMU 的 gt911 模型硬编码 0x5d，QEMU 那套 dts 写 0x5d */
        reg = <0x14>;
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_tsc &pinctrl_tsc_reset>;
        interrupt-parent = <&gpio1>;
        interrupts = <9 0>;
        reset-gpios = <&gpio1 5 GPIO_ACTIVE_LOW>;
        interrupt-gpios = <&gpio1 9 GPIO_ACTIVE_LOW>;
        status = "okay";
        vdd-supply = <&reg_vddio>;
        avdd-supply = <&reg_avdd28>;
    };
};
```

### 关键属性说明

| 属性 | 说明 |
|------|------|
| compatible | 兼容字符串，`goodix,gt9xx` 是 fallback |
| reg | I2C 地址（7 位）。真板写 0x14，QEMU 那套 dts 写 0x5d |
| interrupt-parent | 中断控制器的 phandle |
| interrupts | 中断号（GPIO1_IO09 = GPIO1 的第 9 号） |
| reset-gpios | 复位引脚 |
| interrupt-gpios | 中断引脚（有些驱动需要显式指定） |
| vdd-supply | 数字电源 regulator |
| avdd-supply | 模拟电源 regulator |

## 第三步——配置 pinctrl

触摸屏需要两个 pinctrl 组，咱们分开写：一个用于中断引脚，一个用于复位引脚：

```dts
&iomuxc {
    pinctrl_tsc: tscgrp {
        fsl,pins = <
            /* TSC_INT */
            MX6UL_PAD_GPIO1_IO09__GPIO1_IO09  0x79
        >;
    };

    pinctrl_tsc_reset: tsc_reset {
        fsl,pins = <
            /* TSC_RST */
            MX6UL_PAD_GPIO1_IO05__GPIO1_IO05  0x10B0
        >;
    };
};
```

请您留意这两个引脚（GPIO1_IO09 和 GPIO1_IO05），它们也是 SD 卡（usdhc1）的复位和 VSELECT 引脚。两个设备同时启用就会产生 GPIO 冲突，怎么解决咱们后面讲。

## 第四步——配置 regulator

触摸屏需要两个电源：3.3V 数字电源和 2.8V 模拟电源，咱们在根节点定义：

```dts
/ {
    reg_vddio: regulator-vddio {
        compatible = "regulator-fixed";
        regulator-name = "VDDIO";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        regulator-enable-high = <1>;
    };

    reg_avdd28: regulator-avdd28 {
        compatible = "regulator-fixed";
        regulator-name = "AVDD28";
        regulator-min-microvolt = <2800000>;
        regulator-max-microvolt = <2800000>;
        regulator-enable-high = <1>;
    };
};
```

这些 regulator 实际上是由 PMIC 或 LDO 提供的，设备树里只是告诉内核触摸屏需要这些电源，驱动初始化时会调用 regulator API 来获取，咱们不用额外做什么。

## 第五步——解决 GPIO 冲突

这是笔者踩过的、GT9147 移植最常见的问题。如果您看到这样的报错：

```
pin MX6UL_PAD_GPIO1_IO09 already requested by 1-0014; cannot claim for 2040000.touchscreen
pin MX6UL_PAD_GPIO1_IO05 already requested by 1-0014; cannot claim for 2190000.mmc
```

这就说明 GT9147 的中断/复位引脚和 SD 卡的引脚冲突了。原因是 GT9147 先 probe，占用了这两个引脚，SD 卡（usdhc1）后 probe，发现引脚已被占用，于是失败，咱们就看到了这两行报错。

### 解决方法一：删除 SD 卡的冲突引脚

如果咱们不需要 SD 卡，或者卡在其他地方（比如用 eMMC 启动），可以直接删除 usdhc1 的 pinctrl 里冲突的引脚：

```dts
pinctrl_usdhc1: usdhc1grp {
    fsl,pins = <
        MX6UL_PAD_SD1_CMD__USDHC1_CMD      0x17059
        MX6UL_PAD_SD1_CLK__USDHC1_CLK      0x10071
        MX6UL_PAD_SD1_DATA0__USDHC1_DATA0  0x17059
        MX6UL_PAD_SD1_DATA1__USDHC1_DATA1  0x17059
        MX6UL_PAD_SD1_DATA2__USDHC1_DATA2  0x17059
        MX6UL_PAD_SD1_DATA3__USDHC1_DATA3  0x17059
        MX6UL_PAD_UART1_RTS_B__GPIO1_IO19  0x17059  /* SD1 CD */
        /* 删除下面两行，与 GT911 冲突 */
        /* MX6UL_PAD_GPIO1_IO05__USDHC1_VSELECT    0x17059 */
        /* MX6UL_PAD_GPIO1_IO09__GPIO1_IO09        0x17059 */
    >;
};
```

### 解决方法二：调整 probe 顺序

如果 SD 卡必须用，您可以尝试调整 probe 顺序，让 usdhc1 先于 GT9147 probe。但笔者不推荐这个方法，因为硬件上确实冲突了。

### 解决方法三：使用不同的引脚

如果硬件设计允许，可以把触摸屏的中断/复位引脚改到其他 GPIO 上，这样就不和 SD 卡冲突了。不过这得改板子硬件，对咱们来说不太实际。

## 第六步——验证触摸驱动加载

启动后，咱们检查 dmesg 里的触摸相关日志：

```bash
dmesg | grep -E "goodix|gt9147|touch"
```

您应该看到类似这样的输出：

```
[    2.123456] goodix 1-0014: ID 0x9147
[    2.234567] goodix 1-0014: irq 0, flags 0x0
[    2.345678] goodix 1-0014: Touchscreen registered
[    2.456789] input: Goodix Capacitive TouchScreen as /devices/soc0/soc/2100000.i2c/i2c-1/1-0014/input/input0
```

关键是 `Touchscreen registered` 这一行，您看到它就说明驱动成功注册了输入设备。日志里每行开头的 1-0014 也值得看一眼：这是真板上的输出，对应双轨口径里真板那个 0x14；同样的检查在 QEMU 里跑，这几行印的是 1-005d，那是 QEMU 模型的固定地址，两边都对。

### 检查输入设备

```bash
ls /dev/input/
# 应该看到：event0  mice  mouse0

cat /proc/bus/input/devices
```

您应该看到类似这样的输出：

```
I: Bus=0018 Vendor=0000 Product=0000 Version=0000
N: Name="Goodix Capacitive TouchScreen"
P: Phys=1-0014/input0
S: Sysfs=/devices/soc0/soc/2100000.i2c/i2c-1/1-0014/input/input0
U: Uniq=
H: Handlers=event0 mouse0
B: PROP=2
B: EV=b
B: KEY=400 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
B: ABS=2650000 3
```

## 第七步——触摸测试

### 方法一：evtest 测试

```bash
# 安装 evtest
apt install evtest

# 运行 evtest
evtest /dev/input/event0
```

触摸屏幕，您应该看到类似这样的输出：

```
Event: time 1234567890.123456, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 0
Event: time 1234567890.123456, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 512
Event: time 1234567890.123456, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 300
Event: time 1234567890.123456, -------------- SYN ------------
```

### 方法二：ts_test 测试

如果安装了 tslib：

```bash
apt install tslib-tests
ts_test
```

这会显示一个触摸测试界面，您可以在上面画线、点击。

### 方法三：cat /dev/input/event0

```bash
cat /dev/input/event0 | hexdump -C
```

咱们触摸时应该有数据输出，不触摸时没有输出。

## 第八步——触摸校准

大多数情况下 GT9147 不需要校准，驱动会自动从芯片读取校准参数。但如果坐标准确度有问题，您可以用 tslib 校准：

```bash
# 校准
ts_calibrate

# 测试
ts_test
```

咱们来看校准数据：它会保存在 `/etc/pointercal` 文件里，应用软件（比如 Qt）会读取这个文件。

## 常见问题排查

### 问题一：触摸没有反应

首先确认驱动是否加载：

```bash
dmesg | grep goodix
ls /dev/input/event*
```

如果您没有看到 `/dev/input/event0`，或者 dmesg 里有报错，检查：
1. I2C 地址是否正确（真板实测 0x14；QEMU 侧模型固定 0x5d）
2. I2C 总线是否工作（`i2cdetect -y 1`，真板这颗芯片出现在 0x14，QEMU 里在 0x5d）
3. 中断引脚是否正确

### 问题二：触摸坐标偏移

这种情况通常是屏幕分辨率和触摸报告的分辨率不匹配。GT9147 会报告触摸的绝对坐标（比如 0-1023），咱们需要根据屏幕分辨率缩放。

您可以在应用层处理，或者修改驱动的 resolution 参数。具体方法参考 `drivers/input/touchscreen/goodix.c`。

### 问题三：触摸抖动

触摸抖动，咱们可以从这三个方向排查：
1. 电源噪声：检查 VDD 和 AVDD 的电源质量
2. 中断触发方式：尝试修改中断触发方式（边沿触发 vs 电平触发）
3. 驱动滤波：Goodix 驱动有软件滤波功能，检查配置

### 问题四：多点触摸不工作

检查内核配置：

```bash
zcat /proc/config.gz | grep INPUT_MT
```

应该看到：

```
CONFIG_INPUT_MT=y
CONFIG_INPUT_TOUCHSCREEN=y
```

如果咱们查到的是 `n` 或 `m`，需要开启 `CONFIG_INPUT_MT` 并重新编译内核。

## 下一章预告

到这里，您应该已经有了显示和触摸，图形界面的硬件基础就完整了。

下一篇文章，咱们会讲双网口的移植：

- i.MX6ULL 双 FEC 控制器架构
- KSZ8081 PHY 驱动配置
- RMII 接口设备树编写
- PHY 复位引脚配置
- 网络测试与验证

网络是嵌入式系统的重要外设，有了它您才能做远程调试、网络通信。咱们下一章见。

---

**参考命令速查**

```bash
# 检查触摸驱动
dmesg | grep -E "goodix|gt9147|touch"
ls /dev/input/event*

# 检查 I2C 设备（真板 GT9147 在 0x14，QEMU 里是 0x5d）
i2cdetect -y 1

# 触摸测试
evtest /dev/input/event0
ts_test

# 校准
ts_calibrate

# 检查输入设备属性
cat /proc/bus/input/devices
```

**延伸阅读**

- [Goodix Touchscreen Driver](https://www.kernel.org/doc/html/latest/input/goodix.html) - Goodix 驱动文档
- [Linux Input Subsystem](https://www.kernel.org/doc/html/latest/input/index.html) - 输入子系统文档
- [ tslib Documentation](https://tslib.info/) - tslib 触摸库文档
