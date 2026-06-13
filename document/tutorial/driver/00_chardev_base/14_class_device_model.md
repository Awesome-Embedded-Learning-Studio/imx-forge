---
title: class 与 device 模型
---

# class 和 device 模型 - 自动创建设备节点的幕后机制

## 前言：从手动 mknod 的痛苦说起

写驱动最烦的事情是什么？不是写代码，而是每次加载驱动后都要手动创建设备节点。你肯定经历过这样的流程：加载驱动，然后敲 `mknod /dev/xxx c 主设备号 次设备号`，要是主设备号还是动态分配的，还得先去 `/proc/devices` 里查一遍。说实话，这个过程重复几次就会让人崩溃。

现代 Linux 系统有一个叫 udev/mdev 的机制，它可以监听内核事件然后自动创建设备节点。但这个机制是怎么工作的？驱动程序需要做什么才能触发它？这就是我们要讨论的 class 和 device 模型。

## 从 sysfs 说起：内核的设备表示层

在深入代码之前，我们需要先理解 sysfs。你可以把它想象成一个内核向用户空间展示的"设备地图"。当你挂载 `/sys` 目录时，实际上是在查看内核内部维护的设备层次结构。

```bash
$ ls /sys/
block/  bus/  class/  dev/  devices/  firmware/  kernel/  module/  power/
```

我们关注的是 `/sys/class/` 这个目录。这里按类别组织了系统中的所有设备。当你创建一个字符设备驱动时，如果正确使用了 class 和 device API，这里就会出现对应的条目。

这个目录结构不是摆设，它是 udev/mdev 工作的基础。当驱动程序在 sysfs 中注册设备时，内核会发送一个 uevent 事件，用户空间的设备管理器监听这些事件，然后自动在 `/dev` 下创建对应的设备节点。

所以整个流程是这样的：驱动调用 API → 内核创建 sysfs 条目 → 内核发送 uevent → udev/mdev 创建设备节点。我们的任务就是搞定前两步，后面的由系统自动完成。

## class_create()：创建设备类别

我们首先要创建一个"类"（class）。这个概念听起来很抽象，你可以把它理解为一个设备分类。比如所有的 LED 设备可以归到 `led` 类，所有的 TTY 设备归到 `tty` 类。

在老内核（Linux 4.x）时代，`class_create()` 的签名是这样的：

```c
struct class *class_create(struct module *owner, const char *name);
```

你需要在调用时传入 `THIS_MODULE` 作为 owner 参数。但说实话，内核开发者分析大量驱动代码后发现，这个参数几乎总是被设置为 `THIS_MODULE`。既然如此，为什么不自动推断呢？于是新内核（Linux 5.x+）把这个参数去掉了：

```c
struct class *class_create(const char *name);
```

现在我们只需要传入类名称就可以了。这个名称会出现在 `/sys/class/<name>/` 路径中。比如我们传 `"aes_led"`，就会创建 `/sys/class/aes_led/` 目录。

调用代码非常简单：

```c
struct class *led_class;

led_class = class_create("aes_led");
if (IS_ERR(led_class)) {
    pr_warn("Failed to create class: %ld\n", PTR_ERR(led_class));
    return PTR_ERR(led_class);
}

pr_info("class create success!\n");
```

这里有个细节值得注意。`class_create()` 的返回值需要用 `IS_ERR()` 来检查，而不是直接判断 `== NULL`。这是因为内核使用了一种叫做"错误指针"的机制来传递详细的错误码。如果函数失败，它会返回一个特殊的指针值，这个指针指向的地址包含错误码信息。`IS_ERR()` 判断是否为错误指针，`PTR_ERR()` 提取其中的错误码。

为什么要这样设计？因为如果函数只返回 NULL，调用者就无法知道具体是什么错误（内存不足？参数无效？权限问题？）。通过错误指针机制，内核可以在返回指针的同时传递详细的错误信息。

## device_create()：真正创建设备

有了类之后，我们就可以创建具体的设备了。`device_create()` 的参数多一些，我们逐个来看：

```c
struct device *device_create(
    struct class *class,      /* 设备所属的类 */
    struct device *parent,    /* 父设备，通常填 NULL */
    dev_t devt,               /* 设备号 */
    void *drvdata,            /* 驱动私有数据，通常填 NULL */
    const char *fmt, ...      /* 设备名称，支持 printf 格式化 */
);
```

第一个参数就是我们刚才创建的 `led_class`。设备必须属于某个类，这样才能触发 uevent 机制。

第二个参数是父设备，用于建立设备层次结构。对于简单的字符设备，我们通常填 `NULL` 表示没有父设备。

第三个参数是设备号，这应该是在之前调用 `alloc_chrdev_region()` 时分配的。

第四个参数是驱动私有数据，你可以传入任意指针，之后通过 `dev_get_drvdata()` 获取。如果不需要就填 `NULL`。

第五个参数最有意思，它支持 printf 风格的格式化字符串。这意味着你可以这样批量创建设备：

```c
for (i = 0; i < 3; i++) {
    dev_t dev = MKDEV(major, i);
    device_create(cls, NULL, dev, NULL, "led%d", i);
}

// 创建的结果：
// /dev/led0, /dev/led1, /dev/led2
```

完整的调用代码如下：

```c
struct device *led_device;

led_device = device_create(led_class, NULL, devid, NULL, "AES_LED");
if (IS_ERR(led_device)) {
    pr_warn("Failed to create device: %ld\n", PTR_ERR(led_device));
    class_destroy(led_class);  // 清理已创建的 class
    return PTR_ERR(led_device);
}

pr_info("device create success!\n");
```

当这段代码执行后，系统会发生什么？首先，内核会在 `/sys/class/aes_led/AES_LED/` 创建一个目录，里面包含 `dev`、`uevent`、`subsystem` 等文件。然后内核发送 uevent 事件，udev/mdev 监听到这个事件后，会读取 `dev` 文件获取设备号，然后在 `/dev/` 下创建设备节点。

你可以通过 ls 命令验证设备节点是否创建成功：

```bash
$ ls -l /dev/AES_LED
crw-------    1 root     root      241,   0 ... /dev/AES_LED
```

这里的 `241, 0` 就是主设备号和次设备号，`c` 表示这是一个字符设备。

## udev/mdev 的工作原理

虽然这一部分主要在用户空间，但了解一下对我们理解整个流程很有帮助。udev 是桌面系统和服务器上使用的完整设备管理器，而 mdev 是 BusyBox 提供的简化版本，专门用于嵌入式系统。

mdev 的工作流程大致是这样的：它打开一个 netlink socket 监听内核的 uevent 事件，然后在一个循环中不断接收事件。当接收到设备添加事件时，它会解析事件内容，提取设备信息，然后调用 `mknod()` 创建设备节点。

```c
// mdev 的简化逻辑（伪代码）
void mdev_main(void)
{
    sock = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_KOBJECT_UEVENT);

    while (1) {
        recvmsg(sock, &msg, ...);  // 接收 uevent

        if (strstr(buf, "add@/class/aes_led/AES_LED")) {
            // 从环境变量或事件数据中提取设备号和权限
            mknod("/dev/AES_LED", mode, dev);
        }
    }
}
```

在嵌入式系统中，通常在启动脚本中配置 mdev：

```bash
# /etc/init.d/rcS
echo /sbin/mdev > /proc/sys/kernel/hotplug
```

这样 mdev 就会接管内核的所有热插拔事件。

## 资源清理：逆序原则的重要性

我们前面花了很大篇幅讲如何创建资源，现在要讲如何清理。说实话，这一步做不好，系统真的会炸。

资源清理有一个必须遵守的原则：逆序清理。也就是说，最后创建的资源要最先销毁。为什么要这样？因为后创建的资源可能依赖先创建的资源。如果你先销毁了被依赖的资源，依赖它的资源就会处于"悬空"状态，可能导致内核崩溃或者资源泄漏。

在我们的驱动中，创建顺序是这样的：
```
alloc_chrdev_region() → cdev_add() → class_create() → device_create()
```

所以清理顺序必须是：
```
device_destroy() → class_destroy() → cdev_del() → unregister_chrdev_region()
```

`device_destroy()` 的原型很简单：

```c
void device_destroy(struct class *class, dev_t devt);
```

调用它会删除设备，触发 uevent 事件（这次是删除事件），udev/mdev 会自动删除 `/dev` 节点。

`class_destroy()` 也很简单：

```c
void class_destroy(struct class *cls);
```

它会删除设备类，释放相关资源，`/sys/class/aes_led/` 目录会被删除。

完整的清理函数如下：

```c
static void release_led_handle(struct IMXAesLED *led_handle)
{
    device_destroy(led_handle->char_device_class,
                   led_handle->devid);
    class_destroy(led_handle->char_device_class);
    cdev_del(&led_handle->char_device_handle);
    unregister_chrdev_region(led_handle->devid, LED_CNT);
}
```

## 常见踩坑点

在这个章节的学习过程中，我们踩过一些坑，希望你不用再踩一遍。

第一个坑是清理顺序错误。如果你先调用 `class_destroy()` 再调用 `device_destroy()`，内核会直接崩溃。因为 device 依赖 class，class 销毁了，device 就成了"孤儿"。记住逆序清理这个原则，能省很多麻烦。

第二个坑是忘记检查返回值。`class_create()` 和 `device_create()` 都可能失败，如果不检查就直接使用返回的指针，空指针解引用会立刻触发内核崩溃。这一点真的不能偷懒。

第三个坑是设备节点未创建。当你发现 `/dev/` 下没有预期的设备节点时，不要急着怀疑驱动代码。按这个顺序排查：首先确认驱动是否加载（`lsmod | grep 你的模块名`），然后检查设备号是否分配（`cat /proc/devices | grep 你的驱动名`），接着检查 class 是否创建（`ls /sys/class/`），最后检查 device 是否创建（`ls /sys/class/你的类名/`）。内核日志（`dmesg | grep 你的驱动名`）通常能告诉你问题出在哪里。

## struct class 的更多细节

虽然我们使用 `class_create()` 时不需要传入 class 结构体，但了解一下它的内部结构有助于理解设备模型的工作原理。

```c
struct class {
    const char *name;                           /* 类名称 */

    const struct attribute_group **class_groups;     /* 类本身的属性 */
    const struct attribute_group **dev_groups;       /* 设备的默认属性 */

    int (*dev_uevent)(const struct device *dev,
                      struct kobj_uevent_env *env);  /* 热插拔事件处理 */
    char *(*devnode)(const struct device *dev,
                     umode_t *mode);                    /* 设备节点权限 */

    void (*class_release)(struct class *class);        /* 类释放回调 */
    void (*dev_release)(struct device *dev);           /* 设备释放回调 */

    const struct dev_pm_ops *pm;                       /* 电源管理操作 */
};
```

大部分字段我们用不到，但 `dev_groups` 值得关注。它允许我们为设备创建 sysfs 属性文件。用户空间可以通过读写这些文件与设备交互，这是一种比设备节点更灵活的交互方式。

不过对于简单的字符设备驱动，我们通常不需要关心这些细节。`class_create()` 会用默认值填充结构体，足够应付大部分场景。

## 本章小结

我们从手动创建设备节点的痛苦出发，学习了 Linux 设备模型的基础知识。class 和 device API 不仅仅是自动创建设备节点的工具，它们是驱动程序与系统设备管理框架交互的接口。

通过正确使用 `class_create()` 和 `device_create()`，我们的驱动可以无缝集成到 Linux 系统中。udev/mdev 会自动处理设备节点的创建和删除，用户不需要关心设备号，不需要手动执行 mknod，体验和原生设备一样。

资源清理的逆序原则是本章的重要知识点，这不是某种约定俗成的风格，而是内核对象依赖关系的必然要求。违反这个原则会导致严重的系统问题。

下一章我们会学习驱动中的错误处理模式，包括如何优雅地处理资源分配失败的情况，以及 goto 标签的正确使用方式。虽然 goto 在应用层编程中被认为是不好的实践，但在内核的错误处理中，它却是标准做法。

---

**相关文档：**
- [cdev 和设备号管理](13_cdev_and_device_number.md)
- [驱动错误处理模式](15_error_handling_patterns.md)
