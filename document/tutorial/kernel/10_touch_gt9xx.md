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

请您留意 GPIO1_IO09 这根脚：它在这块板子上有一段争夺史——07 篇战史三里 SD 卡电源调节器占过它，第五步还会遇到另一个争夺者 tsc。先记住它是触摸中断的命根子，第五步细说。

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

## 第五步——排掉 GPIO 冲突

GT9147 移植最容易撞上的一类问题，这块板子在真板上第一次启动就遇上了（2026-10-13 实录）：

```
[    1.952035] imx6ul-pinctrl 20e0000.pinctrl: pin MX6UL_PAD_GPIO1_IO09 already requested by 1-0014; cannot claim for 2040000.touchscreen
[    1.952168] imx6ul-tsc 2040000.touchscreen: error -EINVAL: Error applying setting, reverse things back
```

逐行读：GPIO1_IO09 已经被 1-0014——真板上的 GT9147，双轨口径见 07 篇战史二——在 1.950 秒申请走了；来抢的 2040000.touchscreen 是 imx6ul-tsc，i.MX6ULL 片内的电阻触摸控制器，不是 SD 卡。它 1.952 秒才到，申请的又是 tscgrp 这组引脚（第三步写的那个，组里唯一激活的脚正是 GPIO1_IO09），整组申请失败，-EINVAL 回退，probe 就此收场。

tsc 是从 EVK 参考板抄板级文件时跟来的遗留：参考板配的是电阻屏，tsc 节点开着正好；这块板是电容屏，GT9147 走 I2C，电阻触摸控制器根本用不上。它是 GPIO1_IO09 的最后一个前主人——再往前一段是 07 篇战史三里 SD 卡电源调节器 reg_sd1_vmmc 那桩旧案。

### 解法：把 &tsc 节点从板级 dts 里删掉

板子不用电阻触摸，&tsc 节点就没有存在的理由，整个删掉即可。主线 imx6ul.dtsi 里 tsc 默认就是 status = "disabled"，删掉等于回归主线默认，设备不再 probe。注意删的是 &tsc 节点本身，pinctrl_tsc 这个引脚组要留下——gt9147 还借着它挂中断脚。

删完之后 GPIO1_IO09 只剩触摸一个主人，这几行报错从启动日志里彻底消失，触摸本身不受任何影响——冲突里它从来都是赢家。仓库的板级 dtsi 已经这么改了。同一份 dts 在 QEMU 里症状不同：那边 probe 顺序反过来，tsc 先 probe，死在更早的一步（板级 dtsi 里 xnur-gpios 注释着，驱动要不到这根 GPIO，报 -2 退出），GPIO1_IO09 随后照常归 12 秒才 probe 的 GT911 模型（1-005d）。病根相同、症状不同，删掉 tsc 两边一起痊愈。

## 第六步——验证触摸驱动加载

启动后，咱们检查 dmesg 里的触摸相关日志：

```bash
dmesg | grep -E "goodix|gt9147|touch"
```

真板上实测的输出是这样（2026-10-13）：

```
[    1.950417] Goodix-TS 1-0014: ID 911, version: 1060
[    1.950711] Goodix-TS 1-0014: Direct firmware load for goodix_911_cfg.bin failed with error -2
[    2.027235] input: Goodix Capacitive TouchScreen as /devices/platform/soc/2100000.bus/21a4000.i2c/i2c-1/1-0014/input/input1
```

关键是最后一行 `input: Goodix Capacitive TouchScreen`——驱动成功注册了输入设备。第一行顺手报了芯片身份：ID 911、固件版本 1060，这是真板 GT9147 的自报家门。中间那行固件加载失败 -2 缺的只是可选配置文件 goodix_911_cfg.bin，不碍事，判读思路 [串口日志阅读](../debug/03_serial_log_reading.md) 第四节专门讲过。行首的 1-0014 对应双轨口径里真板的 0x14；同样的检查在 QEMU 里跑，印的是 1-005d、版本 0020——QEMU 模型的固定地址和固件版本，两边都对，这对版本号还是分辨一份日志出自哪条轨的快速特征。

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
S: Sysfs=/devices/platform/soc/2100000.bus/21a4000.i2c/i2c-1/1-0014/input/input1
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
