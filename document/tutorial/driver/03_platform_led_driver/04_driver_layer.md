# 驱动层实现分析 - Platform 和字符设备的结合

## 前言：驱动层的职责

HAL 层封装了硬件操作，那驱动层做什么？驱动层的职责是：和内核框架交互（Platform、字符设备）、管理设备节点、处理用户空间请求。换句话说，驱动层是 HAL 层和内核之间的桥梁。

## 设备结构体

```c
struct platform_led {
    struct led_hw_ctx hw_ctx;  // HAL 层上下文
    dev_t devid;               // 设备号
    struct cdev cdev;          // 字符设备
    struct class *cls;         // 设备类
    struct device *dev;        // 设备
};
```

这个结构体保存了驱动的所有状态。`hw_ctx` 是 HAL 层的硬件上下文，`devid` 是字符设备号，`cdev` 是字符设备结构体，`cls` 是设备类（用于自动创建设备节点），`dev` 是设备结构体。

## Platform Driver 定义

```c
static const struct of_device_id led_of_match[] = {
    {.compatible = "imxaes,led"},
    {/* sentinel */},
};
MODULE_DEVICE_TABLE(of, led_of_match);

static struct platform_driver platform_led_driver = {
    .probe = platform_led_probe,
    .remove = platform_led_remove,
    .driver =
        {
            .name = "platform_led_13",
            .of_match_table = led_of_match,
        },
};

module_platform_driver(platform_led_driver);
```

`led_of_match` 数组定义了支持的设备，`.compatible = "imxaes,led"` 会匹配设备树里 `compatible = "imxaes,led"` 的节点。数组最后必须有一个空元素 `{/* sentinel */}` 作为哨兵。

`MODULE_DEVICE_TABLE(of, led_of_match)` 这个宏有两个作用：让模块加载器知道这个驱动支持哪些设备，以及把设备 ID 信息导出到模块元数据。这样当系统检测到匹配的设备时，就能自动加载对应的驱动模块。

`module_platform_driver()` 是一个便利宏，它展开为 `module_init()` 和 `module_exit()`，你不需要手动写这些初始化/清理代码。

## Probe 函数

Probe 函数是驱动初始化的核心入口。当设备匹配成功后，内核会调用它。我们的 `probe` 函数做了几件事：

首先是分配设备结构体。我们用 `devm_kzalloc()` 分配内存，它会自动在设备卸载时释放。`kzalloc` 的 `z` 表示 zero-initialized（初始化为 0）。

然后是初始化 HAL 层。我们调用 `led_hw_init()` 从设备树获取 GPIO 并配置。如果这一步失败，我们需要返回错误码。

接下来是注册字符设备。`alloc_chrdev_region()` 动态分配一个设备号。`cdev_init()` 初始化字符设备并关联 `file_operations`，`cdev_add()` 把设备注册到内核。

最后是创建设备节点。`class_create()` 创建一个设备类，`device_create()` 创建具体的设备节点。这一步会自动在 `/sys/class/` 下创建对应目录，并在 `/dev/` 下创建设备节点。也就是说，我们不需要手动执行 `mknod` 命令了。

```c
platform_set_drvdata(pdev, g_led);
```

这一行把我们的设备结构体保存到 `platform_device` 里。以后在 `remove` 函数里，可以通过 `platform_get_drvdata()` 取回。

## Remove 函数

当设备卸载时，内核会调用 `remove` 函数。我们用 `platform_get_drvdata()` 取回设备结构体，然后销毁设备节点、设备类，删除字符设备，注销设备号，清理 HAL 层。顺序和 `probe` 里是相反的——先创建的后销毁。

## file_operations

用户空间通过 `/dev/AES_LED` 设备节点和驱动交互。交互的方式由 `file_operations` 定义。我们的 `read` 函数返回当前 LED 状态：如果 LED 点亮返回 '1'，否则返回 '0'。`write` 函数设置 LED 状态：写入 '1' 点亮 LED，写入其他值熄灭 LED。

::: tip 为什么用全局变量 g_led
这里有个设计问题：我们用了一个全局变量 `g_led` 保存设备结构体。对于单设备驱动这没问题，但如果系统里有多个 LED，这就不够灵活了。更好的做法是用 `file->private_data` 保存设备指针，每个打开的文件都能找到对应的设备。
:::

## 小结

本节我们分析了驱动层的实现。`platform_driver` 定义了驱动的元数据和回调函数，`probe` 函数在设备匹配时被调用完成初始化，`remove` 函数在设备卸载时被调用清理资源，`file_operations` 定义了用户空间的交互接口。

至此，我们已经完整分析了 Platform LED 驱动的实现。下一节，我们来看设备树配置，了解硬件信息是如何描述的。

---

<ChapterNav variant="sub">
  <ChapterLink href="03_hal_layer.md" variant="sub">← HAL 层实现</ChapterLink>
  <ChapterLink href="05_device_tree.md" variant="sub">设备树配置 →</ChapterLink>
</ChapterNav>
