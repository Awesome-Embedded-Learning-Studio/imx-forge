# GPIO 输入机制 - 配置和读取那些事儿

上一章我们讲了为什么要先学轮询方式，现在我们深入到代码层面，看看 GPIO 输入到底是怎么工作的。

说实话，第一次写 GPIO 输入驱动的时候，我以为会很复杂。结果发现 Linux 的 GPIO 子系统把事情简化了不少，大部分复杂操作都被封装好了。

## 输入和输出的 API 对比

我们先回顾一下输出设备怎么用 GPIO：

```c
/* 输出模式：LED/蜂鸣器 */
struct gpio_desc *led = gpiod_get(dev, NULL, GPIOD_OUT_LOW);
gpiod_set_value(led, 1);  // 点亮 LED
```

再看输入模式：

```c
/* 输入模式：按键 */
struct gpio_desc *key = gpiod_get(dev, NULL, GPIOD_IN);
int state = gpiod_get_value(key);  // 读取按键状态
```

API 的命名很有规律：
- `gpiod_get()` 获取 GPIO 描述符
- `GPIOD_OUT_LOW`/`GPIOD_IN` 指定方向
- `gpiod_set_value()`/`gpiod_get_value()` 操作 GPIO

::: info 关于 Descriptor API

你可能听说过还有 Legacy API（`gpio_request`、`gpio_direction_input` 之类的）。那些是老接口，现在不推荐用了。Descriptor API 是新的标准，功能更强，也更安全。我们教程统一用 Descriptor API。
:::

## 配置 GPIO 为输入

在我们的硬件抽象层里，初始化函数是这样的：

```c
int key_hw_init(struct device *dev, struct gpio_desc **gpio)
{
    struct gpio_desc *gpiod;

    /* GPIOD_IN 表示配置为输入 */
    gpiod = gpiod_get(dev, NULL, GPIOD_IN);
    if (IS_ERR(gpiod)) {
        return PTR_ERR(gpiod);
    }

    *gpio = gpiod;
    return 0;
}
```

这个 `gpiod_get()` 做了几件事：

1. **解析设备树**——从 `gpios = <&gpio1 18 GPIO_ACTIVE_LOW>` 提取信息
2. **申请 GPIO**——防止被其他驱动占用
3. **配置方向**——设置为输入模式
4. **返回描述符**——后续操作用这个描述符

::: tip 错误处理要重视

`gpiod_get()` 可能失败，比如 GPIO 已经被占用，或者设备树配置错误。所以一定要检查返回值。

`IS_ERR()` 和 `PTR_ERR()` 是内核的错误处理模式。很多内核函数用指针返回结果，成功时返回有效指针，失败时返回错误码编码的"错误指针"。这个模式和普通的返回值判断不太一样，一开始用的时候容易搞混。
:::

## 读取 GPIO 状态

读取状态的代码也很简单：

```c
int key_get_state(struct gpio_desc *gpio)
{
    int val;

    val = gpiod_get_value(gpio);

    /* 返回 0=按下，1=松开 */
    return !val;
}
```

等等，为什么要 `!val` 反转一下？这涉及到 `GPIO_ACTIVE_LOW` 的处理。

## 逻辑值和物理值

GPIO 有两个层面的值：物理电平和逻辑值。

物理电平是实际电压：
- 高电平（3.3V）对应物理 1
- 低电平（0V）对应物理 0

逻辑值是应用层的语义：
- 按键按下对应逻辑 1
- 按键松开对应逻辑 0

我们的硬件是低电平触发，所以物理和逻辑是反着的：

```
物理电平    逻辑值
────────────────────
高（松开） → 0
低（按下） → 1
```

`gpiod_get_value()` 已经帮我们处理了一次转换：

```c
/* 内核内部实现（简化） */
int gpiod_get_value(struct gpio_desc *desc)
{
    int raw_val = gpiod_get_raw_value(desc);  // 读取物理电平

    /* 如果设置了 GPIO_ACTIVE_LOW，反转逻辑值 */
    if (test_bit(GPIOD_FLAG_ACTIVE_LOW, &desc->flags))
        return !raw_val;
    else
        return raw_val;
}
```

所以如果设备树里写了 `GPIO_ACTIVE_LOW`：
- 物理低 → `gpiod_get_value()` 返回 1
- 物理高 → `gpiod_get_value()` 返回 0

但我们的应用层约定是：
- 按键按下 → 返回 0
- 按键松开 → 返回 1

所以需要在 `key_get_state()` 里再反转一次：`return !val`。

::: info 为什么是这种约定？

这个约定是从 LED 驱动继承来的。LED 的约定是：1=亮，0=灭。按键我们就约定：1=松开（高电平），0=按下（低电平）。

实际上这个约定可以随便定，只要驱动和应用层统一就行。但我们为了保持一致性，沿用了 LED 的约定。
:::

## 深入内核源码

如果你想看 `gpiod_get_value()` 的完整实现，它在 `drivers/gpio/gpiolib.c` 里：

```c
int gpiod_get_value(struct gpio_desc *desc)
{
    /* 省略参数检查和锁操作 */

    if (test_bit(GPIOD_FLAG_ACTIVE_LOW, &desc->flags))
        return !gpiod_get_raw_value(desc);
    else
        return gpiod_get_raw_value(desc);
}
EXPORT_SYMBOL(gpiod_get_value);
```

`gpiod_get_raw_value()` 就直接读 GPIO 控制器的寄存器了，具体实现取决于硬件平台。对于 i.MX6ULL，它会读写 GPIO 数据寄存器（`GPIO_DR`）。

## 关于 GPIO 释放

你可能注意到了，我们的硬件抽象层没有释放 GPIO 的函数。这是因为我们用了 `devm_` API：

```c
gpiod = devm_gpiod_get(dev, NULL, GPIOD_IN);
```

`devm_` 前缀表示"managed resource"（托管资源）。当设备卸载时，内核会自动释放这些资源。所以我们的代码里不需要显式调用 `gpiod_put()`。

::: tip 托管资源的好处

托管资源机制最大的好处是防止资源泄漏。你想想，如果驱动在某个错误路径返回，忘记了释放 GPIO，这个 GPIO 就永远被占用了。托管资源自动处理这些清理工作，少写代码还更安全。

当然，我们的教程代码为了演示完整流程，会显示调用释放函数。但在实际工程里，托管资源是更好的选择。
:::

## 小结一下

GPIO 输入的核心就这么几个函数：

```c
/* 1. 获取并配置为输入 */
gpiod = gpiod_get(dev, NULL, GPIOD_IN);

/* 2. 读取状态 */
val = gpiod_get_value(gpiod);

/* 3. （可选）释放 */
gpiod_put(gpiod);
```

剩下的工作就是怎么用这些基本操作实现一个完整的按键驱动了。下一章我们看轮询方式的实现，在 `read()` 函数里循环等待按键事件。

说实话，看完这些代码你会发现，GPIO 输入并没有想象中那么复杂。Linux 的 GPIO 子系统把硬件差异都封装好了，我们用统一的高层 API 就能操作。这种抽象做得挺到位的。

---

**上一章**: [前言](./01_introduction.md) | **下一章**: [轮询实现](./03_polling_implementation.md)
