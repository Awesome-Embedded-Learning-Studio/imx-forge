---
title: Platform 驱动框架
---

# Platform 驱动框架 - Linux 嵌入式驱动的核心

## 前言：为什么需要 Platform 框架

在嵌入式 Linux 系统中，大部分外设都不挂载在任何物理总线上——它们不是 PCI 设备，也不是 USB 设备。CPU 内集成的 GPIO 控制器、定时器、PWM 控制器，以及板载的 LED、按键、蜂鸣器，这些设备如何被内核识别和管理？

答案就是 **Platform 总线**——一条虚拟的软件总线，专门用来管理这类"平台设备"。

::: info Platform 总线的本质
Platform 总线不是真实的物理总线，而是内核为了统一管理方式设计的虚拟框架。它定义了设备如何描述（设备树）、驱动如何注册、匹配如何发生、probe/remove 何时调用。
:::

## Platform 总线的工作原理

### 设备和驱动的匹配流程

```
┌─────────────────┐         ┌─────────────────┐
│  设备树节点      │         │  驱动代码        │
│  compatible     │ ──────▶ │  of_match_table  │
│  "imxaes,led"    │   匹配   │  "imxaes,led"    │
└─────────────────┘         └─────────────────┘
          │                           │
          ▼                           ▼
    platform_device          platform_driver
          │                           │
          └───────▶ 匹配成功 ◀───────┘
                     │
                     ▼
              probe() 函数被调用
```

设备树解析器读取 `.dts` 文件，为每个节点创建 `platform_device`。驱动注册时创建 `platform_driver`。内核通过比较 `compatible` 属性和 `of_match_table` 来匹配两者。

### 匹配的优先级

内核的匹配逻辑有一套优先级（来自 `drivers/base/platform.c`）：

```c
static int platform_match(struct device *dev, struct device_driver *drv)
{
    struct platform_device *pdev = to_platform_device(dev);
    struct platform_driver *pdrv = to_platform_driver(drv);

    /* 1. 首先尝试 OF（设备树）风格匹配 - 嵌入式系统主要走这条路径 */
    if (of_driver_match_device(dev, drv))
        return 1;

    /* 2. 然后尝试 ACPI 风格匹配 - x86 平台用 */
    if (acpi_driver_match_device(dev, drv))
        return 1;

    /* 3. 尝试 ID 表匹配 */
    if (pdrv->id_table)
        return platform_match_id(pdrv->id_table, pdev) != NULL;

    /* 4. 最后回退到驱动名匹配 */
    return (strcmp(pdev->name, drv->name) == 0);
}
```

对于嵌入式系统，主要是第一条：`of_driver_match_device()`。它会逐个比较 `of_match_table` 里的 `compatible` 字符串。

::: tip 匹配失败很常见
刚开始写驱动的时候，我们经常遇到驱动加载了但 `probe` 函数不执行的情况。十有八九是 `compatible` 属性写错了——要么拼写错误，要么大小写不对。内核日志里会告诉你匹配失败，但新手经常忽略这个信息。
:::

## platform_driver 结构体

驱动通过 `platform_driver` 结构体注册到内核：

```c
static const struct of_device_id led_of_match[] = {
    {.compatible = "imxaes,led"},
    {/* sentinel */},  /* 哨兵，标记数组结束 */
};
MODULE_DEVICE_TABLE(of, led_of_match);

static struct platform_driver platform_led_driver = {
    .probe = platform_led_probe,
    .remove = platform_led_remove,
    .driver = {
        .name = "platform_led_13",
        .of_match_table = led_of_match,
    },
};

module_platform_driver(platform_led_driver);
```

### of_match_table 的作用

`of_match_table` 是一个数组，每个元素包含一个 `compatible` 字符串。内核会遍历这个数组，和设备树的 `compatible` 属性比较。

```c
static const struct of_device_id led_of_match[] = {
    {.compatible = "imxaes,led"},      /* 支持的第一个设备 */
    {.compatible = "imxaes,led-v2"},   /* 支持的第二个设备 */
    { /* sentinel */ }                 /* 必须有空元素作为结尾 */
};
```

::: warning sentinel 占位符
注意数组最后的 `{ /* sentinel */ }`，这是个空结构体，用来标记数组结束。内核遍历 `of_match_table` 时会一直找，直到遇到这个空结构体。忘了写这个会导致内核越界访问，panic 是迟早的事。
:::

### MODULE_DEVICE_TABLE 的作用

```c
MODULE_DEVICE_TABLE(of, led_of_match);
```

这个宏有两个作用：

1. 把设备 ID 信息导出到模块元数据，让模块加载器知道这个驱动支持哪些设备
2. 当系统检测到匹配的设备时，能够自动加载对应的驱动模块（如果编译为模块）

### module_platform_driver 宏

```c
module_platform_driver(platform_led_driver);
```

这个便利宏展开后包含了 `module_init()` 和 `module_exit()` 的样板代码：

```c
/* module_platform_driver 的展开（简化版） */
static int __init platform_led_driver_init(void)
{
    return platform_driver_register(&platform_led_driver);
}
module_init(platform_led_driver_init);

static void __exit platform_led_driver_exit(void)
{
    platform_driver_unregister(&platform_led_driver);
}
module_exit(platform_led_driver_exit);
```

用这个宏就不用手写 `init` 和 `exit` 函数了，代码更简洁。

## Probe 函数 - 驱动的初始化入口

`probe` 函数在设备匹配成功后被调用，是驱动的初始化入口。一个标准的 `probe` 函数结构如下：

```c
static int platform_led_probe(struct platform_device *pdev)
{
    int ret;

    /* 1. 分配设备结构体 */
    g_led = devm_kzalloc(&pdev->dev, sizeof(*g_led), GFP_KERNEL);
    if (!g_led)
        return -ENOMEM;

    /* 2. 初始化硬件资源 */
    ret = led_hw_init(&pdev->dev, &g_led->hw_ctx);
    if (ret) {
        dev_err(&pdev->dev, "Failed to init LED hardware: %d\n", ret);
        return ret;
    }

    /* 3. 注册字符设备 */
    ret = alloc_chrdev_region(&g_led->devid, 0, LED_CNT, IMX_LED_NAME);
    if (ret < 0) {
        dev_err(&pdev->dev, "Failed to alloc chrdev region: %d\n", ret);
        goto err_hw;
    }

    cdev_init(&g_led->cdev, &aes_led_fops);
    ret = cdev_add(&g_led->cdev, g_led->devid, LED_CNT);
    if (ret < 0) {
        dev_err(&pdev->dev, "Failed to add cdev: %d\n", ret);
        goto err_region;
    }

    /* 4. 创建设备节点 */
    g_led->cls = class_create(IMX_LED_NAME);
    if (IS_ERR(g_led->cls)) {
        ret = PTR_ERR(g_led->cls);
        goto err_cdev;
    }

    g_led->dev = device_create(g_led->cls, &pdev->dev, g_led->devid, NULL, IMX_LED_NAME);
    if (IS_ERR(g_led->dev)) {
        ret = PTR_ERR(g_led->dev);
        goto err_class;
    }

    /* 5. 保存设备指针 */
    platform_set_drvdata(pdev, g_led);

    dev_info(&pdev->dev, "platform_led probe success\n");
    return 0;

    /* 错误处理 - goto 模式 */
err_class:
    class_destroy(g_led->cls);
err_cdev:
    cdev_del(&g_led->cdev);
err_region:
    unregister_chrdev_region(g_led->devid, LED_CNT);
err_hw:
    led_hw_deinit(&g_led->hw_ctx);
    return ret;
}
```

### Probe 的四个步骤

1. **分配设备结构体** - 用 `devm_kzalloc()` 分配内存，自动管理生命周期
2. **初始化硬件资源** - 获取 GPIO、注册中断、映射寄存器等
3. **注册字符设备** - 分配设备号、初始化 `cdev`、添加到内核
4. **创建设备节点** - 创建 `class` 和 `device`，自动生成 `/dev` 节点

### 错误处理的 goto 模式

```c
err_class:
    class_destroy(g_led->cls);
err_cdev:
    cdev_del(&g_led->cdev);
err_region:
    unregister_chrdev_region(g_led->devid, LED_CNT);
err_hw:
    led_hw_deinit(&g_led->hw_ctx);
```

初始化顺序是 alloc_chrdev_region → cdev_add → class_create → device_create，清理顺序是反过来的。这种逆序清理确保了资源不会泄漏。

::: tip goto 的合理使用
刚学 C 语言时老师都说不要用 `goto`，但内核代码里到处都是 `goto`。在错误处理这种场景，`goto` 是最合适的选择——每一步失败都有对应的清理标签，代码清晰又高效。
:::

## Remove 函数 - 驱动的清理入口

`remove` 函数在设备卸载时被调用，负责清理所有资源：

```c
static void platform_led_remove(struct platform_device *pdev)
{
    struct platform_led *led = platform_get_drvdata(pdev);

    if (led) {
        device_destroy(led->cls, led->devid);
        class_destroy(led->cls);
        cdev_del(led->cdev);
        unregister_chrdev_region(led->devid, LED_CNT);
        led_hw_deinit(&led->hw_ctx);
    }

    dev_info(&pdev->dev, "platform_led removed\n");
}
```

::: info 新版内核的变化
新版内核（Linux 5.x+）`remove` 函数返回 `void`，旧版返回 `int`。内核开发者认为卸载失败也没什么办法处理——返回错误给谁？设备已经卸载了，返回错误也没意义。
:::

## 设备树配置

驱动对应的设备树配置如下：

```dts
imx_aes_led {
    compatible = "imxaes,led";           /* 和驱动的 of_match_table 匹配 */
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_aes_led>;     /* 引脚配置 */
    status = "okay";
    led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>;  /* GPIO 绑定 */
};
```

`compatible` 属性必须和驱动的 `of_match_table` 一字不差，否则匹配失败。

## 小结

Platform 驱动框架的核心要素：

1. **设备树描述硬件** - `compatible` 属性用于匹配
2. **of_match_table 定义支持的设备** - 数组形式，支持多个设备
3. **probe 函数初始化驱动** - 分配结构体、获取硬件、注册设备
4. **remove 函数清理资源** - 逆序释放，确保不泄漏
5. **module_platform_driver 宏简化注册** - 不需要手写 init/exit

::: tip 学习建议
Platform 框架是嵌入式 Linux 驱动开发的基础，几乎所有外设驱动都用这个框架。掌握了 Platform，后面学其他驱动（I2C、SPI）就容易多了。
:::

接下来我们深入 HAL 层设计，看看如何封装硬件操作细节。

---

<ChapterNav variant="sub">
  <ChapterLink href="01_introduction.md" variant="sub">← Platform 框架与 HAL 设计思想</ChapterLink>
  <ChapterLink href="03_hal_layer.md" variant="sub">HAL 层实现 →</ChapterLink>
</ChapterNav>
