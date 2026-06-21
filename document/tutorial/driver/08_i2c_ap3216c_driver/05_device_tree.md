---
title: 设备树配置
---

# 设备树配置 —— 把硬件画进内核的地图

驱动代码写得再漂亮，如果内核压根不知道板子上"有这么个设备"，那也是白搭——`probe` 永远不会被调用。让内核"看见"硬件，就是设备树的活儿。这一节我们要做的是：在 `imx6ull-aes.dtsi` 的 I2C1 总线下，把 AP3216C 这个节点挂上去。好消息是，I2C1 的引脚复用项目早就配好了，我们只需要动一个地方。

## 先看看 i2c1 现在长什么样

打开 `driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi`，找到 `&i2c1` 节点（大约在 288 行）。它默认是这样的：

```dts
/* imx6ull-aes.dtsi，现状 */
&i2c1 {
	clock-frequency = <100000>;          /* I2C 标准速率 100kHz */
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_i2c1>;
	status = "okay";

	magnetometer@e {                     /* mag3110 磁力计 */
		compatible = "fsl,mag3110";
		reg = <0x0e>;
		vdd-supply = <&reg_peri_3v3>;
		vddio-supply = <&reg_peri_3v3>;
		position = <2>;
	};

	fxls8471@1e {                        /* fxls8471 加速度计 */
		compatible = "fsl,fxls8471";
		reg = <0x1e>;
		position = <0>;
		interrupt-parent = <&gpio5>;
		interrupts = <0 8>;
	};
};
```

先把这份"现状"读明白。`clock-frequency = <100000>` 把 I2C1 时钟设成 100kHz，这是 I2C 标准模式；如果你的传感器支持 400kHz 快速模式，硬件布线和上拉电阻跟得上的话可以改大。`pinctrl-0 = <&pinctrl_i2c1>` 引用了引脚复用配置，`status = "okay"` 表示这条总线已启用——这三行说明 I2C1 控制器本身已经就绪，我们一行都不用动。

底下挂着两个设备：`magnetometer@e` 是颗 mag3110 磁力计（地址 `0x0e`），`fxls8471@1e` 是颗加速度计（地址 `0x1e`）。这俩是 NXP 官方 EVK 开发板上的器件，**我们这块 I.MX6U-ALPHA 板上一个都没有**。留着它们，内核启动时会去探测，大概率超时失败、还往日志里刷一堆噪音，所以得删掉。

## 删旧、添新：改完的 i2c1 节点

我们把那两个不存在的设备删掉，换成 AP3216C。改完的 `&i2c1` 节点是这样：

```dts
/* imx6ull-aes.dtsi，修改后 */
&i2c1 {
	clock-frequency = <100000>;
	pinctrl-names = "default";
	pinctrl-0 = <&pinctrl_i2c1>;
	status = "okay";

	ap3216c@1e {
		compatible = "imxaes,ap3216c";
		reg = <0x1e>;
	};
};
```

逐行说清楚这几行的分量。节点名 `ap3216c@1e` 里的 `@1e` 是个"建议性"标注，提示这个设备的 I2C 地址是 `0x1e`——它不参与匹配，但写对了对读代码的人友好。`compatible = "imxaes,ap3216c"` 才是灵魂：内核拿这个字符串去和驱动 `of_match_table` 里登记的项比对，对上了才会触发 `probe`。所以这个字符串必须和上一节驱动代码里 `ap3216c_of_match` 那一栏**一字不差**——一个大小写、一个逗号位置错了，驱动就永远找不到设备（当然，这是正常预期的行为，但是实际上，内核是有奇怪的兜底机制——也就是部分匹配的时候也能搭上线，但是千万别依赖这个兜底机制）。`reg = <0x1e>` 是真正生效的硬件地址，AP3216C 的 7 位从机地址就是 `0x1e`，写错的话 I2C 控制器发出去的信号会石沉大海，只能收到 NACK。

::: warning ⚠️ 踩坑预警
你可能会注意到，被我们删掉的 `fxls8471` 用的也是 `reg = <0x1e>`——它和 AP3216C **地址撞车**。这恰恰说明：如果你忘了删 `fxls8471`，又加了 `ap3216c@1e`，同一条 I2C 总线上就会有两个节点都声明地址 `0x1e`，内核实例化 `i2c_client` 时会打架，大概率谁也起不来。所以"先删干净再添新的"这一步不能偷懒。
:::

## 引脚为什么不用动

你可能纳闷：光加个节点，SCL 和 SDA 的引脚配置呢？答案是项目早就配好了。往上翻到 `imx6ull-aes.dtsi` 的 551 行，能找到 `pinctrl_i2c1`：

```dts
/* imx6ull-aes.dtsi，已有的引脚复用，不用动 */
pinctrl_i2c1: i2c1grp {
	fsl,pins = <
		MX6UL_PAD_UART4_TX_DATA__I2C1_SCL 0x4001b8b0
		MX6UL_PAD_UART4_RX_DATA__I2C1_SDA 0x4001b8b0
	>;
};
```

这两行把 `UART4_TX_DATA` 复用成 `I2C1_SCL`、`UART4_RX_DATA` 复用成 `I2C1_SDA`，那个 `0x4001b8b0` 是电气属性配置（上拉、驱动强度、压摆率等）。I2C1 控制器通过 `pinctrl-0 = <&pinctrl_i2c1>` 引用它，所以引脚层面已经就绪——我们这个传感器又**不用中断**（AP3216C 的 INT 引脚本章不接），所以连中断配置都省了，设备树改到这儿就够了。

::: tip 那个 0x4001b8b0 别乱改
这串数字编码了引脚的上拉电阻、开漏、驱动强度等关键参数。I2C 是开漏总线，**必须**靠上拉电阻把电平拉高，这个配置值里就包含了上拉使能。如果你手贱改错了，总线电平拉不上来，表现就是通信完全卡死、SCL/SDA 一直是低电平。配错了别怀疑驱动，先回来查这个值。
:::

## 编译与验证

设备树改完，重新编译 DTB。在内核源码树里执行 `make dtbs`（具体命令在下一节编译测试里细讲），把生成的 `.dtb` 烧到板子上启动。如果一切顺利，I2C 核心层会读到我们这个 `ap3216c@1e` 节点，实例化出一个 `i2c_client`，再去匹配驱动。

验证设备有没有被识别，最直接的办法是看 sysfs。AP3216C 挂在 I2C1（总线号 0），地址 `0x1e`，所以对应的目录名是 `0-001e`：

```bash
ls /sys/bus/i2c/devices/
# 期望看到：0-001e

cat /sys/bus/i2c/devices/0-001e/name
# 期望输出：ap3216c
```

`0-001e` 里，`0` 是总线号、`001e` 是地址。`name` 文件输出 `ap3216c`，说明内核已经"看见"这颗芯片了。注意这一步**只验证设备树**——此时驱动模块还没加载，但 `i2c_client` 已经会被创建出来。如果这一步就没看到 `0-001e`，那问题出在设备树（地址写错、`status` 没改成 `okay`、或者 DTB 没更新），别急着去查驱动。

## 小结

这一节我们在 `imx6ull-aes.dtsi` 的 I2C1 节点下挂上了 AP3216C：删掉板子上不存在的 mag3110 和 fxls8471，加上 `compatible = "imxaes,ap3216c"`、`reg = <0x1e>` 的子节点，引脚复用因为项目早就配好而无需改动。到这里，硬件地图画完了，驱动代码也写完了，最后一节我们就把它们编译出来、烧到板子上、用真实数据验证整套链路。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_driver_layer.md" variant="sub">← AP3216C 驱动层实现</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">编译与上板测试 →</ChapterLink>
</ChapterNav>
