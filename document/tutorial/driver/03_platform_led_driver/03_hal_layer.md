# HAL 层实现分析 - 封装硬件细节的艺术

## 前言：为什么要单独研究 HAL 层

在上一节里，我们了解了 Platform 框架和 HAL 的设计思想。现在我们要深入 HAL 层的实现细节，看看这些封装是如何工作的。

HAL 层的代码量不大，但每一个函数都和内核的 GPIO 子系统紧密相关。如果不理解底层机制，就很难写出健壮的 HAL 代码。而且说实话，HAL 层写得好不好，直接决定了驱动代码的质量。

## GPIO Descriptor API

这里用到了 **GPIO Descriptor API**，这是内核推荐的 GPIO 操作方式。在老版本的内核里，大家用 `gpio_request()` / `gpio_set_value()` 这类函数。但这些函数有个问题：用的是整数编号的 GPIO，不直观，而且和设备树脱节。

从 Linux 4.x 开始，内核引入了 Descriptor API：用 `struct gpio_desc *` 代替整数编号，自动从设备树获取 GPIO 配置，支持 `GPIO_ACTIVE_LOW` 等标志。我们的 HAL 层就是基于这套 API 实现的。

## led_hw_init 实现

```c
int led_hw_init(struct device* dev, struct led_hw_ctx* ctx) {
    if (!dev || !ctx) {
        pr_err("Invalid parameters\n");
        return -EINVAL;
    }

    /* Get GPIO descriptor from device tree ("led-gpio" property) */
    ctx->gpio = devm_gpiod_get(dev, "led", GPIOD_OUT_LOW);
    if (IS_ERR(ctx->gpio)) {
        int err = PTR_ERR(ctx->gpio);
        dev_err_probe(dev, err, "Failed to get led GPIO\n");
        return err;
    }

    dev_info(dev, "LED hardware initialized\n");
    return 0;
}
```

`devm_gpiod_get()` 是获取 GPIO 的核心函数。我们来看看内核的实现（`drivers/gpio/gpiolib.c:4856`）：

```c
struct gpio_desc *__must_check gpiod_get(struct device *dev, const char *con_id,
                     enum gpiod_flags flags)
{
    return gpiod_get_index(dev, con_id, 0, flags);
}
```

它实际上调用了 `gpiod_get_index()`，用索引 0 获取第一个 GPIO。这个函数会从设备树查找对应的 GPIO 属性，解析 GPIO 配置（编号、标志等），然后返回一个 `gpio_desc` 结构体。

这里有个容易混淆的地方：设备树里我们写的是 `led-gpio`（单数），但这里传的是 `"led"`。内核的匹配逻辑是这样的：首先尝试 `<con_id>-gpio`（即 `led-gpio`），如果找不到，尝试 `<con_id>-gpios`（即 `led-gpios`），还找不到，尝试 `<con_id>`（即 `led`）。所以设备树里的属性名和驱动里的 con_id 应该对齐。

`GPIOD_OUT_LOW` 这个参数表示把 GPIO 配置为输出，初始值为低电平。但如果设备树里指定了 `GPIO_ACTIVE_LOW`，这里会自动处理。具体来说，`GPIOD_OUT_LOW` 会让 GPIO 设置为"逻辑 0"，如果声明了 `GPIO_ACTIVE_LOW`，物理电平会是高电平。这就是 Descriptor API 的好处——它会自动处理 `GPIO_ACTIVE_LOW`，你不需要在代码里反转逻辑。

`devm_` 前缀表示"设备管理"。用 `devm_gpiod_get()` 获取的 GPIO，会在设备卸载时自动释放，不需要手动调用 `gpiod_put()`。但我们的 HAL 层还是提供了 `led_hw_deinit()` 函数，保持接口的完整性。如果将来要扩展到非 `devm_` API，这个函数就有用了。

## led_hw_deinit 实现

```c
void led_hw_deinit(struct led_hw_ctx* ctx) {
    if (!ctx) {
        return;
    }

    /* GPIO is managed by devm_, no need to free explicitly */
    pr_info("LED hardware deinitialized\n");
}
```

这个函数目前是空的，因为 GPIO 是由 `devm_` 机制管理的。但我们保留它，有两个原因：保持接口对称性（有 init 就有 deinit），以及为将来可能的扩展预留。如果将来你改用非 `devm_` API（比如 `gpiod_get()` 而不是 `devm_gpiod_get()`），就需要在这里添加 `gpiod_put(ctx->gpio)`。

## led_set_status 实现

```c
void led_set_status(struct led_hw_ctx* ctx, bool status) {
    if (!ctx || !ctx->gpio) {
        return;
    }

    /* GPIOD API handles active_low automatically */
    gpiod_set_value(ctx->gpio, status ? 1 : 0);
}
```

`gpiod_set_value()` 的内部逻辑是这样的：如果设备树里声明了 `GPIO_ACTIVE_LOW`，逻辑 1 → 物理低电平，逻辑 0 → 物理高电平。这个反转是 GPIO 子系统自动处理的，驱动代码不需要关心。

## led_get_status 实现

```c
bool led_get_status(struct led_hw_ctx* ctx) {
    if (!ctx || !ctx->gpio) {
        return false;
    }

    return gpiod_get_value(ctx->gpio) != 0;
}
```

类似地，`gpiod_get_value()` 返回的也是逻辑值，已经处理了 `GPIO_ACTIVE_LOW`。

::: tip HAL 层的优势总结
1. 封装细节：驱动层不需要知道 GPIO 是从设备树获取的，也不需要知道使用的是 Descriptor API
2. 易于测试：可以提供 mock 的 HAL 层进行单元测试
3. 易于扩展：如果要支持 PWM 调光，只需要修改 HAL 层，驱动层代码完全不用动
:::

## 小结

本节我们深入分析了 HAL 层的实现。`devm_gpiod_get()` 的 flags 参数决定初始状态，`gpiod_set_value()` 自动处理 `GPIO_ACTIVE_LOW`，设备树属性名和驱动 con_id 要匹配，`devm_` 机制自动管理资源。HAL 层的优势在于封装细节、易于测试和扩展。

接下来，我们进入驱动层，看看如何把这些 HAL 接口集成到完整的 Platform 驱动中。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_platform_framework.md" variant="sub">← Platform 驱动框架</ChapterLink>
  <ChapterLink href="04_driver_layer.md" variant="sub">驱动层实现 →</ChapterLink>
</ChapterNav>
