# 驱动实现详解 - 逐行拆解代码

前面我们回顾了 Platform 框架和 GPIO 子系统，现在我们来逐行分析蜂鸣器驱动的实现。说实话，这个驱动代码量不大，但每个函数都值得仔细看看。

## 设备结构体

先来看设备结构体：

```c
struct beep_dev {
    dev_t           dev_num;
    struct cdev     cdev;
    struct class    *class;
    struct device   *device;
    struct gpio_desc *gpio;
};
```

和 LED 驱动相比，这里少了 HAL 层的上下文结构体，直接包含 `gpio_desc` 指针。这是因为蜂鸣器操作很简单——就是设置 GPIO 电平，不需要单独的 HAL 层。

::: tip 适度抽象原则
HAL 层不是必须的。如果硬件操作简单，直接在驱动里写也没问题。过度抽象反而增加代码复杂度，还可能影响性能。
:::

还有一个全局变量 `beep_data`，用来保存设备指针：

```c
static struct beep_dev *beep_data;
```

这个全局变量给 `file_operations` 用——`open` 函数把它存到 `private_data`，`write` 函数再取出来用。

## Probe 函数

`probe` 函数是驱动的入口，匹配成功后内核会调用它。我们把它拆开来看。

### 分配设备结构体

```c
dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
if (!dev) {
    return -ENOMEM;
}
beep_data = dev;
```

`devm_kzalloc` 分配内存并初始化为零。和普通 `kzalloc` 不同，`devm_` 版本会自动跟踪内存，设备卸载时自动释放。

::: info GFP_KERNEL 含义
`GFP_KERNEL` 表示这是内核常规内存分配，可以睡眠等待。如果在中断上下文或持有自旋锁时分配内存，需要用 `GFP_ATOMIC`。
:::

### 获取 GPIO

```c
dev->gpio = devm_gpiod_get(&pdev->dev, "beep", GPIOD_OUT_HIGH);
if (IS_ERR(dev->gpio)) {
    int err = PTR_ERR(dev->gpio);
    dev_err_probe(&pdev->dev, err, "Failed to get beep GPIO\n");
    return err;
}
```

这里用 `devm_gpiod_get()` 获取 GPIO，第二个参数 `"beep"` 对应设备树属性名 `beep-gpios`。第三个参数 `GPIOD_OUT_HIGH` 表示配置为输出，初始逻辑值 1。

::: warning dev_err_probe 的好处
`dev_err_probe` 是新版内核的宏，它会处理 `EPROBE_DEFER` 延迟 probing 的情况。如果 GPIO 控制器还没初始化，返回 `EPROBE_DEFER`，内核会稍后重试。
:::

### 动态分配设备号

```c
int err = alloc_chrdev_region(&dev->dev_num, 0, 1, BEEP_NAME);
if (err < 0) {
    dev_err(&pdev->dev, "Failed to allocate device number\n");
    return err;
}
```

`alloc_chrdev_region` 动态分配设备号，避免硬编码主设备号导致冲突。第一个参数是传出参数，内核会把分配到的设备号写到这里。

### 初始化并注册 cdev

```c
cdev_init(&dev->cdev, &beep_fops);
dev->cdev.owner = THIS_MODULE;
err = cdev_add(&dev->cdev, dev->dev_num, 1);
if (err < 0) {
    dev_err(&pdev->dev, "Failed to add cdev\n");
    goto unregister_region;
}
```

`cdev_init` 初始化 cdev 结构体，`THIS_MODULE` 宏告诉内核这个 cdev 属于当前模块。`cdev_add` 把 cdev 添加到内核，这时候设备就正式注册了。

::: tip THIS_MODULE 的作用
`THIS_MODULE` 防止模块在使用时被卸载。如果忘了设置这个字段，在某些情况下可能会遇到奇怪的问题——模块被卸载了但还有进程在使用设备，然后内核就 panic 了。
:::

### 创建设备节点

```c
dev->class = class_create(BEEP_NAME);
if (IS_ERR(dev->class)) {
    err = PTR_ERR(dev->class);
    dev_err(&pdev->dev, "Failed to create class\n");
    goto del_cdev;
}

dev->device = device_create(dev->class, NULL, dev->dev_num,
                            NULL, BEEP_NAME);
if (IS_ERR(dev->device)) {
    err = PTR_ERR(dev->device);
    dev_err(&pdev->dev, "Failed to create device\n");
    goto destroy_class;
}
```

`class_create` 创建设备类，出现在 `/sys/class` 下。`device_create` 创建具体设备，这一步会自动在 `/dev` 下创建设备节点。

::: info 新版内核的变化
新版内核 `class_create` 只需要类名参数，旧版还需要 `THIS_MODULE`。如果编译时报错，可能需要调整代码或升级内核。
:::

### 错误处理

```c
destroy_class:
    class_destroy(dev->class);
del_cdev:
    cdev_del(&dev->cdev);
unregister_region:
    unregister_chrdev_region(dev->dev_num, 1);
return err;
```

错误处理用 goto 模式逆序清理资源。创建顺序是 alloc_chrdev_region → cdev_add → class_create → device_create，清理顺序是反过来的 device_destroy → class_destroy → cdev_del → unregister_chrdev_region。

::: tip goto 的合理使用
错误处理用 goto 是内核代码的标准做法。每一步失败都有对应的清理标签，资源不会泄漏，代码逻辑也清晰。
:::

## Remove 函数

`remove` 函数在设备卸载时被调用：

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

    device_destroy(dev->class, dev->dev_num);
    class_destroy(dev->class);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "Beep driver removed\n");
}
```

注意到 `remove` 的返回类型是 `void`（新版内核）。卸载时首先要确保蜂鸣器关闭，然后逆序清理资源。

::: tip 卸载前的清理
卸载驱动前确保设备处于安全状态很重要。如果蜂鸣器正在响，卸载驱动后它还会继续响，用户体验很差。对于电机等设备，可能还有安全隐患。
:::

## file_operations

用户空间通过 `/dev/beep` 设备节点和驱动交互，具体接口由 `file_operations` 定义。

### open 和 release

```c
static int beep_open(struct inode *inode, struct file *filp)
{
    filp->private_data = beep_data;
    pr_info("beep: device opened\n");
    return 0;
}

static int beep_release(struct inode *inode, struct file *filp)
{
    pr_info("beep: device released\n");
    return 0;
}
```

`open` 函数把设备指针保存到 `private_data`，这样 `write` 函数可以访问。这是内核驱动的常见模式。

### write 函数

`write` 函数是核心，处理用户空间的写入请求：

```c
static ssize_t beep_write(struct file *filp, const char __user *buf,
                          size_t count, loff_t *ppos)
{
    struct beep_dev *dev = filp->private_data;

    if (!dev) {
        return -ENODEV;
    }

    if (count != 1) {
        return -EINVAL;
    }

    u8 val;
    if (copy_from_user(&val, buf, 1)) {
        return -EFAULT;
    }

    if (val == BEEP_ON) {
        gpiod_set_value(dev->gpio, 0);
        pr_info("beep: ON (GPIO set to LOW)\n");
    } else if (val == BEEP_OFF) {
        gpiod_set_value(dev->gpio, 1);
        pr_info("beep: OFF (GPIO set to HIGH)\n");
    } else {
        return -EINVAL;
    }

    return 1;
}
```

::: warning 极性问题的暴露
这里 `BEEP_ON` 对应 GPIO 值 0，`BEEP_OFF` 对应 GPIO 值 1。但设备树声明了 `GPIO_ACTIVE_HIGH`，逻辑 0 应该对应物理低电平，蜂鸣器应该不响才对。这说明驱动代码和设备树声明有矛盾。
:::

### BEEP_ON 和 BEEP_OFF 的定义

```c
static const u8 BEEP_ON  = 0;
static const u8 BEEP_OFF = 1;
```

这个定义看起来有点反直觉。通常我们认为 `ON = 1`，`OFF = 0`。但这里反过来了，可能是硬件实际接线和设备树声明不一致导致的。

::: tip 命名规范
驱动代码里定义的 `ON/OFF` 是"逻辑状态"，不是物理电平。如果设备树是 `GPIO_ACTIVE_LOW`，逻辑 ON 对应物理低电平，逻辑 OFF 对应物理高电平。
:::

## file_operations 结构体

```c
static const struct file_operations beep_fops = {
    .owner   = THIS_MODULE,
    .open    = beep_open,
    .release = beep_release,
    .write   = beep_write,
};
```

这个结构体告诉内核：用户空间打开设备时调用 `beep_open`，关闭时调用 `beep_release`，写入时调用 `beep_write`。

::: info owner 字段
`owner = THIS_MODULE` 防止模块在使用时被卸载。如果用户打开了设备但还没关闭，模块卸载会被拒绝，返回 `EBUSY`。
:::

## 小结

蜂鸣器驱动的实现要点：

1. 用 `devm_kzalloc()` 分配设备结构体，自动管理内存
2. 用 `devm_gpiod_get()` 获取 GPIO，自动管理资源
3. 注册字符设备和创建设备节点，暴露 `/dev/beep` 接口
4. `file_operations` 实现用户空间接口，`write` 处理控制请求
5. 卸载时确保蜂鸣器关闭，然后逆序清理资源

驱动代码在 GPIO 极性处理上有问题——`BEEP_ON = 0` 但设备树声明 `GPIO_ACTIVE_HIGH`，这明显不对。下一节我们分析设备树配置，看看怎么解决这个问题。

---

<ChapterNav variant="sub">
  <ChapterLink href="02_gpio_polarity.md" variant="sub">← GPIO 极性配置</ChapterLink>
  <ChapterLink href="04_build_and_test.md" variant="sub">编译测试与调试 →</ChapterLink>
</ChapterNav>
