---
title: 新 API 设备结构体
---

# 新 API 中的设备结构体 - 从全局变量到面向对象

## 前言：全局变量的混乱时代

还记得我们最早写那个简单驱动的时候吗？代码里到处都是全局变量。一个设备需要设备号、cdev 结构、class 指针、device 指针，我们就定义了一堆全局变量。当时觉得挺简单的，反正只有一个设备，全局变量就全局变量吧。

但后来问题来了。假设板子上有 3 个 LED，每个 LED 都需要独立的控制。我们怎么办？定义 `devid1, devid2, devid3`？定义 `cdev1, cdev2, cdev3`？定义 `cls1, cls2, cls3`？代码量直接翻三倍，维护成本也是三倍。更糟糕的是，如果需要支持 8 个 LED 呢？16 个呢？难道要定义 16 组变量？

这时候我们就意识到，需要一种更好的组织方式。把描述一个设备所需的所有信息打包到一个结构体中，这样要支持多个设备只需要定义一个数组或者动态分配多个结构体实例。这就是面向对象思想在 C 语言中的应用。

## 设备结构体的基本思想

虽然 C 语言不是面向对象语言，但这不妨碍我们用面向对象的思想来组织代码。面向对象的核心是把数据（属性）和操作数据的方法（行为）打包在一起。在内核驱动开发中，"方法"的部分由 file_operations 回调函数实现，"属性"的部分则由设备结构体来实现。

一个简单的设备结构体可能是这样的：

```c
struct led_device {
    dev_t devid;              /* 设备号 */
    struct cdev cdev;         /* 字符设备 */
    struct class *cls;        /* 设备类 */
    struct device *dev;       /* 设备 */
    int major;                /* 主设备号 */
    int minor;                /* 次设备号 */
};
```

现在如果需要支持多个设备，代码就简单多了：

```c
struct led_device led1;
struct led_device led2;
struct led_device led3;

/* 或者用数组 */
struct led_device leds[8];
```

这样无论有多少设备，代码量都不会线性增长。操作设备的函数只需要接受一个设备结构体指针，就能访问这个设备的所有信息。

## struct IMXAesLED 的设计

我们的 LED 驱动中定义了这样一个结构体：

```c
struct IMXAesLED {
    dev_t devid;                         /* 设备号 */
    struct cdev char_device_handle;      /* 字符设备 */
    struct class* char_device_class;     /* 设备类 */
    struct device* char_device_device;   /* 设备 */
};
```

我们来逐个分析这些成员。`devid` 存储分配给此设备的设备号，这在设备创建和销毁时都需要用到。

`char_device_handle` 是字符设备的核心结构体。这里我们使用完整的 `struct cdev` 而不是指针，这是有意的设计。使用完整结构体意味着不需要动态内存分配，简化了内存管理。在内核中，能避免动态分配就避免，因为内存分配可能失败，失败后还需要错误处理。对于固定大小的结构体，直接嵌入在父结构体中更安全。

`char_device_class` 是指向设备类的指针。这里用指针是因为 `struct class` 通常由 `class_create()` 返回，而且多个设备可以共享同一个 class。没必要在每个设备结构体中都嵌入一个完整的 class 结构体。

`char_device_device` 是指向设备结构体的指针，用于 sysfs 表示。和 class 一样，这也是指针，由 `device_create()` 返回。

你可能注意到这里的命名有点特别：`char_device_handle` 而不是简单的 `cdev`，`char_device_class` 而不是 `class`。这种长命名虽然敲起来麻烦，但在复杂代码中能减少混淆。当你几个月后再看这段代码，或者别人来维护你的代码时，能一眼看出这个变量是做什么的。

## 与老驱动的对比

老驱动（v1）使用的是静态主设备号，没有设备结构体封装：

```c
/* chardev_led_v1_01_driver_main.c */
static const char* CHARDEV_NAME = "AES_LED";
static const int CHARDEV_MAJOR = 200;  // 静态指定主设备号

static struct cdev aes_cdev;
static struct class *aes_class;
static struct device *aes_device;

// 分散的全局变量
```

这种方式简单直接，但有明显的缺点。静态主设备号可能导致冲突，如果 200 号已经被占用，驱动注册就会失败。而且所有变量都是全局的，没有组织在一起，代码可读性差。

新驱动（v2）改用动态分配设备号，设备信息封装在结构体中：

```c
/* chardev_led_v2_02_driver_main.c */
static const char* CHARDEV_NAME = "AES_LED";
static const int LED_CNT = 1;

struct IMXAesLED {
    dev_t devid;
    struct cdev char_device_handle;
    struct class* char_device_class;
    struct device* char_device_device;
} led_handle;  // 单一实例

// 封装的设备结构体
```

这种方式虽然代码量多了一些，但好处是明显的。设备号动态分配避免冲突，设备信息封装在一起易于理解，而且扩展到多设备非常方便。

## private_data 模式

设备结构体解决了数据组织的问题，但还有一个问题：当用户程序调用 `open()`、`read()`、`write()` 时，驱动如何知道用户操作的是哪个设备？在多设备场景下，这个问题尤其重要。

内核提供的解决方案是 `struct file` 中的 `private_data` 字段。这是一个 `void *` 指针，驱动可以自由使用。通常的做法是在 `open()` 时把设备结构体指针存进去，在其他函数中取出来用。

```c
static int aes_chardev_open(struct inode* inode, struct file* filp)
{
    pr_info("Device: %s called open!\n", CHARDEV_NAME);

    /* 设置私有数据 */
    filp->private_data = &led_handle;
    return 0;
}
```

这样在 `read()`、`write()` 等函数中就能访问设备结构体了：

```c
static ssize_t aes_chardev_read(struct file* filp, char __user* buf,
                                size_t cnt, loff_t* offt)
{
    /* 从 filp 获取设备结构体 */
    struct IMXAesLED *dev = filp->private_data;

    /* 现在可以访问设备的所有信息 */
    // dev->devid, dev->char_device_handle, etc.

    /* ... */
}
```

在 `release()` 中可以清理这个指针：

```c
static int aes_chardev_release(struct inode* inode, struct file* filp)
{
    pr_info("Device: %s called close!\n", CHARDEV_NAME);

    /* 释放私有数据 */
    filp->private_data = NULL;
    return 0;
}
```

`private_data` 模式的真正威力在多设备场景下体现出来。假设我们有 3 个 LED，可以通过次设备号判断用户打开的是哪个：

```c
/* 假设有 3 个 LED */
struct IMXAesLED led1, led2, led3;

static int led_open(struct inode *inode, struct file *filp)
{
    int minor = MINOR(inode->i_rdev);  // 通过次设备号判断

    struct IMXAesLED *dev;
    switch (minor) {
        case 0: dev = &led1; break;
        case 1: dev = &led2; break;
        case 2: dev = &led3; break;
        default: return -ENODEV;
    }

    /* 关键：把设备结构体保存到 filp->private_data */
    filp->private_data = dev;
    return 0;
}
```

这样 `read()` 和 `write()` 就不需要知道是哪个设备，它们直接从 `private_data` 取出设备结构体指针即可。

## 单设备 vs 多设备

目前的驱动是单设备实现，只有一个全局实例：

```c
/* 全局设备实例 */
struct IMXAesLED led_handle;

static int __init chardev_led_v2_02_init(void)
{
    /* 只初始化一个设备 */
    init_led_handle(&led_handle);
    return 0;
}
```

如果需要支持多个 LED，扩展起来非常方便。一种简单的方法是用数组：

```c
/* 支持最多 8 个 LED */
#define MAX_LEDS 8

static struct IMXAesLED leds[MAX_LEDS];
static dev_t devid;  /* 共享一个主设备号 */

static int __init chardev_led_init(void)
{
    int i;
    int ret;

    /* 一次申请 8 个次设备号 */
    ret = alloc_chrdev_region(&devid, 0, MAX_LEDS, "multi_led");
    if (ret < 0)
        return ret;

    /* 初始化每个设备 */
    for (i = 0; i < MAX_LEDS; i++) {
        leds[i].devid = MKDEV(MAJOR(devid), i);
        init_led_handle(&leds[i]);
    }

    return 0;
}

static int led_open(struct inode *inode, struct file *filp)
{
    int minor = MINOR(inode->i_rdev);

    if (minor >= MAX_LEDS)
        return -ENODEV;

    filp->private_data = &leds[minor];  /* 选择对应的设备 */
    return 0;
}
```

这种方式适合设备数量固定的情况。如果设备数量是动态的，可以使用链表或者其他动态数据结构。内核中有很多现成的数据结构可以使用，比如 `list_head` 链表、`idr` 树等。

## 真实代码分析

让我们看看实际驱动中是怎么使用设备结构体的。首先是全局实例的定义：

```c
static const char* CHARDEV_NAME = "AES_LED";
static const int LED_CNT = 1;

struct IMXAesLED {
    dev_t devid;
    struct cdev char_device_handle;
    struct class* char_device_class;
    struct device* char_device_device;
} led_handle;  /* 全局实例 */
```

注意这里我们把结构体定义和变量声明合在一起了，直接在结构体定义后面写了 `led_handle`，这样它就成为一个全局变量。在 C 语言中这是合法的，虽然这种写法在大型项目中不太常见（通常结构体定义放在头文件中，变量声明放在源文件中），但对于小的驱动来说很方便。

初始化函数中，我们传递设备结构体指针给初始化函数：

```c
static int __init chardev_led_v2_02_init(void)
{
    pr_info("=== led driver using new api ===\n");

    /* 硬件初始化 */
    led_hw_init();

    /* 设备初始化 */
    init_led_handle(&led_handle);

    pr_info("========================\n");
    return 0;
}
```

这种设计把不同层次的初始化分开：`led_hw_init()` 负责硬件相关的初始化（寄存器映射、GPIO 配置等），`init_led_handle()` 负责设备接口的初始化（设备号、cdev、class、device）。职责分离让代码更清晰。

真实测试输出如下：

```
[   84.387622] === led driver using new api ===
[   84.387644] Step 0: Request MMU Mappings by ioremap
[   84.387710] IMX6U_CCM_CCGR1    = 0xc59d421e (phys: 0x20c406c)
...
[   84.387922] LED Init OK!
[   84.387931] Init the User Interfaces and driver handles
[   84.387944] LED handle get the device number: major: 241, minor: 0
[   84.387966] cdev series api called success!
[   84.388037] class create success!
[   84.388557] device create success!
[   84.388580] ========================
```

可以看到设备号动态分配为 241，如果用静态分配，这个号很可能是要手动指定的，而且可能会和其他设备冲突。

在 file_operations 回调中使用 `private_data`：

```c
static int aes_chardev_open(struct inode* inode, struct file* filp)
{
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
    filp->private_data = &led_handle;  /* 设置私有数据 */
    return 0;
}

static ssize_t aes_chardev_write(struct file* filp, const char __user* buf,
                                 size_t cnt, loff_t* offt)
{
    /* 可以通过 private_data 访问设备 */
    // struct IMXAesLED *dev = filp->private_data;

    /* ... 其他操作 ... */
}
```

虽然在这个单设备驱动中，`private_data` 看起来有点多余（我们只有一个全局设备结构体），但保持这个习惯是有意义的。当驱动扩展到多设备时，不需要修改 file_operations 的实现，只需要在 `open()` 中根据次设备号选择不同的设备结构体即可。

## 结构体设计的一些思考

设备结构体的设计有一些通用原则值得注意。单一职责原则告诉我们，设备结构体应该只包含设备管理相关的信息，不要把业务逻辑混进去。比如 LED 的当前状态可以放在结构体中，但控制 LED 的逻辑函数不应该作为函数指针放在结构体里。

内聚性也很重要。相关的信息应该放在一起，不相关的应该分离。设备号、cdev、class、device 都是设备管理的基本要素，放在一起很合理。但如果把一些与设备管理无关的东西（比如统计数据缓存）也塞进去，就会让结构体变得臃肿。

可扩展性是另一个考虑因素。从单设备到多设备的扩展应该是平滑的，不需要大幅重构代码。我们的设计满足这一点：单设备时用全局实例，多设备时用数组或动态分配，file_operations 的实现基本不变。

## 本章小结

设备结构体封装是从"能跑"到"专业"的关键一步。虽然简单的驱动用全局变量也能工作，但当系统变复杂时，缺乏组织的数据会变成维护噩梦。

面向对象思想在 C 语言中的应用主要体现在结构体设计上。把相关的数据打包在一起，通过指针传递，就能实现类似面向对象的封装效果。虽然 C 语言没有类和继承，但通过合理的结构体设计和函数约定，完全可以实现良好的代码组织。

`private_data` 模式是连接设备模型和 file_operations 的桥梁。通过在 `open()` 时保存设备结构体指针，在其他回调函数中取出使用，我们可以让 file_operations 的实现与具体设备解耦。

从单设备到多设备的扩展，体现了良好设计的价值。当需求变化时，不需要推倒重来，只需要做一些局部调整。这正是软件工程中"开闭原则"的体现——对扩展开放，对修改关闭。

下一章我们会深入分析一个完整的新 API 驱动，把前面学到的所有知识串联起来。你会看到设备结构体、错误处理、class/device 模型是如何在真实代码中协同工作的。

---

**相关文档：**
- [cdev 和设备号管理](13_cdev_and_device_number.md)
- [class 和 device 模型](14_class_device_model.md)
- [驱动错误处理模式](15_error_handling_patterns.md)
