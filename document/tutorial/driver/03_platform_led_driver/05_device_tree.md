# 设备树严格对齐 - 驱动的另一半

## 前言：设备树是驱动的"另一半"

现在我们常说"设备驱动"，但实际上是"设备 + 驱动"——设备树描述硬件，驱动描述逻辑。两者必须严格对齐，否则驱动找不到设备，或者设备信息读取错误。这一节我们详细分析 LED 的设备树配置，以及它和驱动的对应关系。

## 设备树文件结构

我们的设备树文件是 `imx6ull-aes-16_tutorial_platform_led.dts`：

```dts
/dts-v1/;
#include "imx6ull.dtsi"
#include "imx6ull-aes.dtsi"

/ {
    model = "Awesome Embedded Studio IMX6ULL Example Driver";
    compatible = "fsl,imx6ull-14x14-evk", "fsl,imx6ull";

    imx_aes_led {
        compatible = "imxaes,led";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_aes_led>;
        status = "okay";
        led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
    };
};

&iomuxc {
    pinctrl_aes_led: led_grp {
        fsl,pins = <
            MX6UL_PAD_GPIO1_IO03__GPIO1_IO03    0x10B0
        >;
    };
};
```

## compatible 属性

```dts
compatible = "imxaes,led";
```

这是设备树最重要的属性！它和驱动的 `of_device_id` 匹配表对应。驱动里我们写的是：

```c
static const struct of_device_id led_of_match[] = {
    {.compatible = "imxaes,led"},
    {/* sentinel */},
};
```

只有设备树的 `compatible` 和驱动的 `of_match_table` 匹配，内核才会调用驱动的 `probe` 函数。如果对不上，驱动永远不会被加载。

## pinctrl 配置

```dts
pinctrl-names = "default";
pinctrl-0 = <&pinctrl_aes_led>;
```

`pinctrl` 是 pin control 的缩写，用于配置引脚功能。`pinctrl-names` 定义了一组配置状态的名称，`"default"` 表示默认状态。`pinctrl-0` 引用具体的 pinctrl 配置（定义在 `&iomuxc` 节点里）。

`&iomuxc` 是引用语法，相当于"追加到 iomuxc 节点"。`iomuxc` 是 NXP i.MX 系列的 pin controller 节点。`pinctrl_aes_led: led_grp` 定义了一个标签 `pinctrl_aes_led`，供前面的 `pinctrl-0 = <&pinctrl_aes_led>` 引用。`led_grp` 是节点名，可以自由选择。

`fsl,pins` 是 NXP 特定的属性名（不是通用的设备树标准），格式是 `<引脚复用宏 配置值>`。`MX6UL_PAD_GPIO1_IO03__GPIO1_IO03` 表示把 GPIO1_IO03 引脚复用为 GPIO1_IO03 功能。`0x10B0` 是配置值，来自芯片手册的寄存器配置。

这个 `0x10B0` 是根据手册的 PAD 寄存器每一位含义算出来的。具体怎么算，可以参考芯片手册的 IOMUXC 章节。说实话，这个值很繁琐，通常直接抄参考设计的。

## led-gpio 属性

```dts
led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;
```

这是 GPIO 的绑定描述。格式是 `<GPIO控制器 引脚编号 标志>`。`&gpio1` 引用 GPIO 控制器 #1，`3` 是这个控制器的第 3 号 GPIO，`GPIO_ACTIVE_LOW` 表示低电平有效（按下/点亮时电平为低）。

⚠️ **注意**：这里的属性名是 `led-gpio`（单数），不是 `led-gpios`（复数）。内核有一套兜底机制，但建议严格对齐。驱动里我们传的参数是 `"led"`，对应设备树属性名 `led-gpio`。内核的匹配逻辑是这样的：首先尝试 `<con_id>-gpio` → `led-gpio`，如果找不到，尝试 `<con_id>-gpios` → `led-gpios`，还找不到，尝试 `<con_id>` → `led`。

::: warning 设备树和驱动必须对齐
驱动代码和设备树声明要一致。如果设备树是 `GPIO_ACTIVE_LOW`，驱动应该：逻辑 1 表示响（物理高电平），逻辑 0 表示静音（物理低电平）。但如果硬件实际是低电平触发，设备树应该声明 `GPIO_ACTIVE_LOW`，这样逻辑值会被自动反转。
:::

## 小结

本节我们详细分析了设备树配置。`compatible` 属性和驱动的 `of_match_table` 匹配，`pinctrl` 配置引脚功能，GPIO 绑定描述 GPIO 控制器和配置，驱动和设备树必须严格对齐。设备树的语法很繁琐，但它是连接硬件和软件的桥梁。写设备树时，建议多参考芯片手册和参考设计，不要凭空想象。

接下来，我们进入最后的环节：编译和测试。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_driver_layer.md" variant="sub">← 驱动层实现</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">编译与测试 →</ChapterLink>
</ChapterNav>
