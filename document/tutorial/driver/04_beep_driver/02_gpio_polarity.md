# GPIO 极性配置 - 一个容易被忽略的坑

## 前言：为什么极性配置很重要

在 LED 驱动教程中，我们学习了 Platform 框架和 HAL 层设计。对于蜂鸣器驱动，Platform 框架部分你已经掌握了——它和 LED 驱动几乎一样。

蜂鸣器驱动的真正价值在于：**它暴露了一个常见的问题——GPIO 极性配置错误**。这是新手最容易踩的坑，也是本教程的核心内容。

::: warning 真实案例
我们的蜂鸣器驱动代码里 `BEEP_ON = 0`（逻辑 0），但设备树声明 `GPIO_ACTIVE_HIGH`（高电平触发）。这明显是矛盾的，但驱动居然"能用"。为什么呢？因为硬件实际接线和声明不一致。这是一个典型的极性配置问题。
:::

## 逻辑值 vs 物理电平

首先理解两个概念：

| 概念 | 说明 |
|------|------|
| **逻辑值** | 驱动代码里使用的值（0 或 1），表示"开"或"关" |
| **物理电平** | GPIO 引脚的实际电平（高或低），用 LOW/HIGH 表示 |

GPIO 子系统的设计理念是：**驱动代码使用逻辑值，GPIO 子系统自动转换为物理电平**。

```c
/* 驱动代码写的是逻辑值 */
gpiod_set_value(desc, 1);  /* 逻辑 1 = 开 */

/* GPIO 子系统根据设备树自动转换 */
/* 如果 GPIO_ACTIVE_HIGH：逻辑 1 → 物理高电平 */
/* 如果 GPIO_ACTIVE_LOW：  逻辑 1 → 物理低电平 */
```

## GPIO_ACTIVE_* 的含义

### GPIO_ACTIVE_HIGH

表示**逻辑值和物理电平一致**：

| 逻辑值 | 物理电平 | 蜂鸣器状态 |
|--------|----------|-----------|
| 0      | 低       | 静音      |
| 1      | 高       | 响        |

### GPIO_ACTIVE_LOW

表示**逻辑值和物理电平相反**（自动反转）：

| 逻辑值 | 物理电平 | 蜂鸣器状态 |
|--------|----------|-----------|
| 0      | 高（反转）| 静音      |
| 1      | 低（反转）| 响        |

::: tip 如何选择？
这取决于硬件接线。如果蜂鸣器在高电平时响，用 `GPIO_ACTIVE_HIGH`。如果在低电平时响，用 `GPIO_ACTIVE_LOW`。设备树应该描述硬件的实际特性，不要在驱动代码里做极性反转。
:::

## devm_gpiod_get 的 flags 参数

`devm_gpiod_get()` 的第三个参数决定 GPIO 的初始配置：

```c
struct gpio_desc *devm_gpiod_get(struct device *dev,
                                 const char *con_id,
                                 int flags)
```

flags 的可选值：

| 值 | 含义 |
|----|------|
| `GPIOD_ASIS` | 不改变当前状态 |
| `GPIOD_IN` | 配置为输入 |
| `GPIOD_OUT_LOW` | 配置为输出，初始逻辑值 0 |
| `GPIOD_OUT_HIGH` | 配置为输出，初始逻辑值 1 |

::: warning 注意"逻辑值"
`GPIOD_OUT_LOW` 和 `GPIOD_OUT_HIGH` 设置的是**逻辑值**，不是物理电平。如果设备树声明了 `GPIO_ACTIVE_LOW`，逻辑值会被自动反转。
:::

### 蜂鸣器的初始状态

蜂鸣器驱动应该确保**默认静音**，否则驱动加载后蜂鸣器一直响，用户体验很差。

```c
/* 如果硬件是高电平触发，应该用 GPIOD_OUT_LOW */
dev->gpio = devm_gpiod_get(&pdev->dev, "beep", GPIOD_OUT_LOW);
/* 逻辑 0 → 物理低电平 → 蜂鸣器静音 ✓ */

/* 如果硬件是低电平触发，应该用 GPIOD_OUT_HIGH */
dev->gpio = devm_gpiod_get(&pdev->dev, "beep", GPIOD_OUT_HIGH);
/* 逻辑 1 → 物理低电平（反转）→ 蜂鸣器静音 ✓ */
```

## gpiod_set_value 的极性反转

`gpiod_set_value()` 会自动处理极性反转：

```c
void gpiod_set_value(struct gpio_desc *desc, int value)
{
    /* 如果设置了 ACTIVE_LOW 标志，value 会被反转 */
    if (test_bit(GPIOD_FLAG_ACTIVE_LOW, &desc->flags))
        value = !value;

    /* 设置物理电平 */
    gpiod_set_raw_value(desc, value);
}
```

驱动代码只需要写逻辑值，GPIO 子系统会自动处理反转。

## 设备树配置

### 标准写法

```dts
beep {
    compatible = "imxaes,beep";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_beep>;

    /* 高电平触发 */
    beep-gpios = <&gpio5 1 GPIO_ACTIVE_HIGH>;
};
```

### 常见错误

#### 错误 1：极性声明和硬件不符

```dts
/* 硬件实际是低电平触发，但声明了高电平 */
beep-gpios = <&gpio5 1 GPIO_ACTIVE_HIGH>;
```

这会导致驱动代码逻辑和硬件行为不一致。

#### 错误 2：驱动代码写反

```c
/* 设备树声明 GPIO_ACTIVE_HIGH，但驱动写反了 */
static const u8 BEEP_ON  = 0;  /* 应该是 1 */
static const u8 BEEP_OFF = 1;  /* 应该是 0 */
```

虽然可能"能用"（因为硬件和声明都反了），但代码逻辑混乱，维护困难。

::: tip 推荐做法
设备树应该描述硬件的实际特性。如果发现极性不对，优先修改设备树，而不是改驱动代码。硬件接线不容易改，设备树才是描述硬件的地方。
:::

## 调试方法

### 通过 sysfs 测试极性

```bash
# 导出 GPIO（假设是 GPIO 161 = 5*32 + 1）
echo 161 > /sys/class/gpio/export

# 配置为输出
echo out > /sys/class/gpio/gpio161/direction

# 测试高电平
echo 1 > /sys/class/gpio/gpio161/value
# 听蜂鸣器是否响

# 测试低电平
echo 0 > /sys/class/gpio/gpio161/value
```

如果高电平时蜂鸣器响，说明是高电平触发，设备树应该用 `GPIO_ACTIVE_HIGH`。

### 通过 debugfs 查看

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/gpio | grep -i "beep"
```

应该能看到 GPIO 的当前状态：

```
gpio-161 (                    |beep              ) out hi
```

`161` 是 GPIO 编号，`out hi` 表示配置为输出且当前是高电平。

## 驱动代码分析

蜂鸣器驱动的极性问题：

```c
/* 驱动代码 */
static const u8 BEEP_ON  = 0;  /* 逻辑 0 */
static const u8 BEEP_OFF = 1;  /* 逻辑 1 */

static ssize_t beep_write(struct file *filp, const char __user *buf,
                          size_t count, loff_t *ppos)
{
    /* ... */
    if (val == BEEP_ON) {
        gpiod_set_value(dev->gpio, 0);  /* 写逻辑 0 */
        pr_info("beep: ON (GPIO set to LOW)\n");
    } else if (val == BEEP_OFF) {
        gpiod_set_value(dev->gpio, 1);  /* 写逻辑 1 */
        pr_info("beep: OFF (GPIO set to HIGH)\n");
    }
    /* ... */
}
```

```dts
/* 设备树 */
beep-gpios = <&gpio5 1 GPIO_ACTIVE_HIGH>;
```

### 问题分析

设备树声明 `GPIO_ACTIVE_HIGH`，表示：
- 逻辑 1 → 物理高电平
- 逻辑 0 → 物理低电平

但驱动代码：
- `BEEP_ON = 0`，写逻辑 0 → 物理低电平 → 蜂鸣器应该静音
- 但日志显示 "beep: ON"，说明代码认为蜂鸣器响了

这说明**硬件实际是低电平触发**，但设备树声明了 `GPIO_ACTIVE_HIGH`。

### 修复方法

修改设备树：

```dts
beep-gpios = <&gpio5 1 GPIO_ACTIVE_LOW>;  /* 改为 LOW */
```

或者修改驱动代码：

```c
static const u8 BEEP_ON  = 1;  /* 改为 1 */
static const u8 BEEP_OFF = 0;  /* 改为 0 */
```

::: tip 推荐修改设备树
优先修改设备树，因为设备树才是描述硬件的地方。驱动代码应该假设设备树是正确的。
:::

## 卸载时确保安全状态

蜂鸣器驱动的 `remove` 函数有关闭蜂鸣器的逻辑：

```c
static void beep_remove(struct platform_device *pdev)
{
    struct beep_dev *dev = beep_data;

    if (!dev) {
        return;
    }

    /* 卸载驱动时确保蜂鸣器关闭 */
    if (dev->gpio) {
        gpiod_set_value(dev->gpio, BEEP_OFF);
        pr_info("beep: turned OFF during driver removal\n");
    }

    /* ... 清理其他资源 ... */
}
```

这是个好习惯——卸载驱动时确保设备处于"安全"状态。

::: tip 安全状态
对于蜂鸣器，安全状态是静音。对于电机，安全状态可能是停止转动。对于继电器，安全状态可能是断开。卸载驱动前确保设备处于安全状态很重要。
:::

## 小结

GPIO 极性配置的要点：

1. **理解逻辑值和物理电平的区别** - 驱动代码用逻辑值，GPIO 子系统自动转换
2. **设备树描述硬件特性** - 高电平触发用 `GPIO_ACTIVE_HIGH`，低电平触发用 `GPIO_ACTIVE_LOW`
3. **选择正确的初始化 flags** - 确保驱动加载后设备处于安全状态
4. **调试时验证极性** - 用 sysfs 和 debugfs 确认极性配置正确

::: warning 极性不匹配是常见问题
驱动"能用"不代表配置正确。如果发现代码逻辑混乱（比如 ON=0, OFF=1），优先检查设备和驱动的极性是否匹配。
:::

接下来我们分析驱动实现，看看完整代码是如何组织的。

---

<ChapterNav variant="sub">
  <ChapterLink href="01_introduction.md" variant="sub">← 蜂鸣器驱动介绍</ChapterLink>
  <ChapterLink href="03_driver_impl.md" variant="sub">驱动实现详解 →</ChapterLink>
</ChapterNav>
