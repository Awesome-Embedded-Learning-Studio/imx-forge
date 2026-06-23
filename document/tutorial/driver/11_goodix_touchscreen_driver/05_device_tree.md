---
title: 设备树配置
---

# 设备树配置 —— gt9147@5d 节点与引脚

这一节看设备树。和 RTC 一样，好消息是 **GT9147 的节点已经在板级 dtsi 里写好了**（`driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi` 的 `i2c2` 下），主线 goodix 默认编译进内核，开机自动 probe。我们的任务是读懂这个节点每个属性对应驱动里的什么、确认它生效，并指出一处可以改进的小问题。

::: tip 学习目标
看懂 alpha 板 `gt9147@5d` 节点的每个属性（`compatible`/`reg`/`interrupts`/`reset-gpios`/`interrupt-gpios`/`vdd,avdd-supply`/`pinctrl`）对应 `goodix.c` 里的什么；理清「`interrupts` 属性 → `client->irq`」和「`irq-gpios` → 复位时操控 INT」是两套东西；学会确认 goodix 已生效。
:::

## goodix 设备树绑定

主线在 `Documentation/devicetree/bindings/input/touchscreen/goodix.yaml` 定义了 goodix 的设备树契约。常用的属性：

| 属性 | 必填 | 含义 |
|------|------|------|
| `compatible` | 是 | `"goodix,gt9147"` 等，命中驱动的 `of_match` |
| `reg` | 是 | I2C 从机地址（GT9147 是 `0x5d`） |
| `interrupts` | 是 | 中断描述，驱动据此拿 `client->irq` |
| `reset-gpios` | 否 | 复位引脚，驱动用它复位 IC |
| `irq-gpios` | 否 | 中断引脚 GPIO，驱动在复位序列里操控它（切换地址模式） |
| `AVDD28-supply` / `VDDIO-supply` | 否 | 模拟/IO 电源 regulator |
| `touchscreen-size-x/y` | 否 | 覆盖从 IC 读到的分辨率 |
| `touchscreen-inverted-x/y`、`touchscreen-swapped-x-y` | 否 | 坐标翻转/互换修正 |

## alpha 板 `gt9147@5d` 节点逐行解读

板级 dtsi 里（`i2c2` 下）长这样：

```dts
/* imx6ull-aes.dtsi:183 —— alpha 板的 GT9147 节点 */
gt9147: gt9147@5d {
    compatible = "goodix,gt9147", "goodix,gt9xx";   /* 命中 goodix.c 的 of_match */
    reg = <0x5d>;                                    /* I2C2 上的从机地址 0x5d */
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_tsc &pinctrl_tsc_reset>;   /* INT + RST 两个引脚的复用 */
    interrupt-parent = <&gpio1>;
    interrupts = <9 0>;                              /* GPIO1_IO09，下降沿触发 */
    reset-gpios = <&gpio1 5 GPIO_ACTIVE_LOW>;        /* RST = GPIO1_IO05 */
    interrupt-gpios = <&gpio1 9 GPIO_ACTIVE_LOW>;    /* INT = GPIO1_IO09 */
    status = "okay";
    vdd-supply = <&reg_vddio>;                       /* IO 电源 */
    avdd-supply = <&reg_avdd28>;                     /* 模拟电源 AVDD28 */
};
```

逐个对照驱动：

| 属性 | 值 | 对应 `goodix.c` 里的什么 |
|------|-----|--------------------------|
| `compatible` | `"goodix,gt9147"` | 命中 `goodix_of_match`（goodix.c:1551），触发 `goodix_ts_probe` |
| `reg` | `0x5d` | `client->addr`，`goodix_i2c_read/write` 的 I2C 目标地址 |
| `interrupts` | `<9 0>`（gpio1 第 9 脚） | I2C 核心把它转成中断号填进 `client->irq`，`goodix_request_irq` 用它 |
| `reset-gpios` | `gpio1 5` | `goodix_get_gpio_config` 用 `devm_gpiod_get(dev, "reset")` 拿到，`goodix_reset` 操控它 |
| `vdd/avdd-supply` | `reg_vddio` / `reg_avdd28` | `devm_regulator_get(dev, "VDDIO"/"AVDD28")`，probe 里上电 |
| `pinctrl-0` | `pinctrl_tsc` + `pinctrl_tsc_reset` | 把 `GPIO1_IO09`/`GPIO1_IO05` 复用为 GPIO |

## 中断号 vs IRQ GPIO：两套东西别搞混

这里有个特别容易踩的坑，必须说清楚。goodix 的中断涉及**两个不同的东西**：

1. **`interrupts` 属性 → `client->irq`**：这是真正用于 `request_irq` 的中断号。I2C 核心在实例化 `i2c_client` 时，从 `interrupts = <9 0>` 解析出 `GPIO1_IO09` 对应的中断号，填进 `client->irq`。**只要这个在，触摸上报就能工作。**

2. **`irq-gpios` 属性 → `ts->gpiod_int`**：这是「INT 引脚的 GPIO 描述符」，驱动在**复位序列**（`goodix_reset_no_int_sync`，goodix.c:775）里操控它——拉高/拉低 INT 来切换 GT9147 的 I2C 地址模式（`0x14` vs `0x5d`）。它**不直接用于 request_irq**。

::: warning ⚠️ alpha 板 dtsi 用的是 `interrupt-gpios`，而 7.1 goodix 期望 `irq-gpios`
`goodix_get_gpio_config`（goodix.c:983）用 `devm_gpiod_get_optional(dev, "irq", GPIOD_IN)` 拿 INT 的 GPIO——gpiod 框架会找名为 `irq-gpios` 的属性。但 alpha 板 dtsi 写的是 **`interrupt-gpios`**（一字之差），gpiod 找不到，`ts->gpiod_int` 会是 NULL。

后果：`goodix.c` 走 `IRQ_PIN_ACCESS_NONE` 路径，**跳过复位序列里的 INT 操控**（不复位 IC、不切地址）。但因为 `client->irq` 来自 `interrupts` 属性、仍然有效，**中断上报和基本触摸照常工作**——IC 用上电默认状态。

如果你想让 goodix 完整跑复位序列、稳稳切换到 `0x5d` 地址模式，板级 dts 应把 `interrupt-gpios` 改成 **`irq-gpios`**（符合 goodix.yaml binding）。本章配套的 `22_tutorial_goodix_touchscreen` 设备树就用了规范的 `irq-gpios`。
:::

## pinctrl：两个引脚的复用

`pinctrl-0 = <&pinctrl_tsc &pinctrl_tsc_reset>` 引用两组引脚复用配置（在 dtsi 的 `&iomuxc` 里定义）：

- `pinctrl_tsc`：把 `GPIO1_IO09` 配成 GPIO（中断输入脚）。
- `pinctrl_tsc_reset`：把 `GPIO1_IO05` 配成 GPIO（复位输出脚）。

这两组 pinctrl 在 alpha 板 dtsi 里都已配好。pinctrl 子系统的细节我们在 [02_pinctrl_gpio](../02_pinctrl_gpio/01_introduction) 章讲过，这里不重复。

## 确认 goodix 已生效

到板子上确认：

```bash
# 1. 看注册的 input 设备（找名字含 Goodix 的）
cat /proc/bus/input/devices | grep -A6 -i goodix
# N: Name="Goodix Capacitive TouchScreen"
# P: Phys=input/ts
# B: PROP=2
# H: Handlers=event0  ← 记住这个 eventN
# ...

# 2. 启动日志里有 probe + 读到的芯片 ID
dmesg | grep -i goodix
# Goodix-TS 2-005d: ID 9147, version: 0000   ← ID 9147 = GT9147

# 3. /dev/input/eventN 存在
ls /dev/input/
```

看到 `Name="Goodix Capacitive TouchScreen"`、dmesg 里 `ID 9147`，就说明主线 goodix 已经驱动起 GT9147。下一节我们用 `evtest`、`tslib` 操作这个 `/dev/input/eventN`。

## 小结

这一节我们读懂了 `gt9147@5d` 节点：`compatible` 命中驱动、`reg` 是 I2C 地址、`interrupts` 提供真正用于 `request_irq` 的 `client->irq`、`reset-gpios`/`irq-gpios` 给复位序列用、两路 `*-supply` 上电。还指出 alpha 板 dtsi 里 `interrupt-gpios` 与 7.1 goodix 期望的 `irq-gpios` 一字之差（不影响基本触摸，但建议规范化）。下一节上板，用 evtest/tslib 把多点触摸跑起来。

---

<ChapterNav variant="sub">
  <ChapterLink href="04_driver_layer.md" variant="sub">← 关键机制深挖</ChapterLink>
  <ChapterLink href="06_build_and_test.md" variant="sub">启用主线 goodix 与验证 →</ChapterLink>
</ChapterNav>
