---
title: 设备树配置
---

# 设备树配置 —— 唤醒 ECSPI3，挂上 ICM-20608

和 I2C 那篇不同，我们这块板子的 `imx6ull-aes.dtsi` **默认没有启用 ECSPI3**——连个挂载设备的节点都没有。所以 SPI 这边的设备树活儿要重一些：得先把引脚复用配上，再把 ECSPI3 控制器唤醒，最后才轮到挂 ICM-20608。我们分两步走。

## 第一步：引脚复用 pinctrl_ecspi3

ICM-20608 接在 ECSPI3 上，需要四根线：SCLK、MOSI、MISO，再加一个片选 CS。在 I.MX6U-ALPHA 板上，这四根线复用的是 UART2 的四个引脚。我们在 `imx6ull-aes.dtsi` 的 `iomuxc` 节点里加一个 `pinctrl_ecspi3` 子节点：

```dts
/* imx6ull-aes.dtsi，iomuxc 节点内新增 */
pinctrl_ecspi3: ecspi3grp {
    fsl,pins = <
        MX6UL_PAD_UART2_TX_DATA__GPIO1_IO20   0x10b0  /* CS   */
        MX6UL_PAD_UART2_RX_DATA__ECSPI3_SCLK  0x10b1  /* SCLK */
        MX6UL_PAD_UART2_RTS_B__ECSPI3_MISO    0x10b1  /* MISO */
        MX6UL_PAD_UART2_CTS_B__ECSPI3_MOSI    0x10b1  /* MOSI */
    >;
};
```

这里有个值得留意的细节：第一行把 `UART2_TX_DATA` 复用成了 **`GPIO1_IO20`**，而不是 `ECSPI3_SS0`。也就是说，片选这根线我们没有交给 SPI 控制器的硬件 SS，而是接管成一个普通 GPIO、由软件（准确地说是 SPI 核心）来拉。为什么这么做？因为上一节我们看到 `spi-imx.c` 设了 `use_gpio_descriptors = true`——它就是靠设备树的 `cs-gpios` 拿到这个 GPIO、由核心统一管控片选的。所以这里 CS 走 GPIO、驱动用 `use_gpio_descriptors`，这两边是配套的，缺一不可。后面三行把 UART2 的 RX/RTS/CTS 复用成 SCLK/MISO/MOSI，`0x10b1` 是那些引脚的电气属性。

## 第二步：启用 ecspi3、配片选、挂 ICM-20608

引脚配好，接下来在 `imx6ull-aes.dtsi` 里追加 `&ecspi3` 节点。ECSPI3 控制器本身的"骨架"（寄存器地址、中断、时钟）定义在更底层的 `imx6ull.dtsi` 里，默认是 `disabled`，我们这里把它唤醒并挂上设备：

```dts
/* imx6ull-aes.dtsi，新增 */
&ecspi3 {
    fsl,spi-num-chipselects = <1>;                 /* 这条总线 1 个片选 */
    cs-gpios = <&gpio1 20 GPIO_ACTIVE_LOW>;        /* CS = GPIO1_IO20，低有效 */
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_ecspi3>;
    status = "okay";

    icm20608@0 {
        compatible = "imxaes,icm20608";
        spi-max-frequency = <8000000>;             /* 8MHz */
        reg = <0>;                                 /* 接在 CS0 */
    };
};
```

这几行每一行都有分量。`fsl,spi-num-chipselects = <1>` 告诉控制器驱动这条总线只有一个片选。`cs-gpios = <&gpio1 20 GPIO_ACTIVE_LOW>` 是整套设备树里最容易出错的一行——它指定片选用 `gpio1` 的 20 号引脚、低电平有效，正好对应我们第一步配的 `GPIO1_IO20`。SPI 核心在注册控制器时会读这一行、把 GPIO 取成描述符存进 `controller->cs_gpiods[]`，每次传输前后自动拉低/拉高。

::: warning ⚠️ 踩坑预警
`cs-gpios` 这行配错或漏配，是最常见的"SPI 看着成功但设备没反应"的元凶。配错了，核心要么不知道拿哪个 GPIO 当片选、要么拿错引脚，结果 CS 永远拉不低，设备收不到时钟沿、读出来的全是 `0x00` 或 `0xFF`。这一行务必和引脚复用里的 GPIO 对得上。
:::

`status = "okay"` 把控制器从默认的 `disabled` 唤醒——这一行不改，前面全是空气。底下的 `icm20608@0` 才是真正的设备节点：`@0` 表示它挂在 CS0 上，`reg = <0>` 再次确认这一点；`compatible = "imxaes,icm20608"` 是和驱动配对的暗号，必须和 `icm20608_of_match` 里那串完全一致；`spi-max-frequency = <8000000>` 声明这颗芯片最高能跑 8MHz，SPI 核心会取"控制器能力"和"设备声明"两者的最小值作为实际频率，所以这里别手滑多加个零，否则可能超出芯片承受范围。

## 编译与验证

改完设备树，`make dtbs` 重新编译 DTB，烧到板子启动。SPI 设备的识别情况看 sysfs，挂法是 `<总线号>:<片选>`：

```bash
ls /sys/bus/spi/devices/
# 期望看到类似：spi0.0（具体总线号取决于 ECSPI3 是第几个注册的）

cat /sys/bus/spi/devices/spi0.0/modalias
# 期望输出：imxaes,icm20608
```

`spi0.0` 里，`spi0` 是控制器编号、`.0` 是片选号。`modalias` 输出 `imxaes,icm20608`，说明 SPI 核心已经把这个节点实例化成 `spi_device` 了。和 I2C 一样，这一步只验证设备树——驱动模块还没加载。如果这里就没看到设备，先回头查 ECSPI3 的 `status`、`cs-gpios` 和引脚复用，别急着翻驱动。

## 小结

这一节我们从零唤醒了 ECSPI3：配了 `pinctrl_ecspi3`（CS 走 GPIO、其余三根线复用 ECSPI3），用 `cs-gpios` 把片选交给 SPI 核心管，挂上了 `compatible = "imxaes,icm20608"` 的 ICM-20608 子节点。到这里硬件地图画完、驱动代码也写完，最后一节就把它们编译上板，读出真实的六轴数据。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_driver_layer.md" variant="sub">← ICM-20608 驱动层实现</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">编译与上板测试 →</ChapterLink>
</ChapterNav>
