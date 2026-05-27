# Input 子系统架构 - 理解分层设计的艺术

上一章我们说了 Input 子系统的种种好处，现在我们来深入理解它的架构。说实话，刚开始学的时候我被这些层次搞晕了——Input Core、Handler、Drivers，它们到底怎么协作？后来亲手写了一个驱动，看了内核源码，才明白这个设计的精妙之处。

## Input Core：事件分发的中心

Input Core 是 Input 子系统的核心，代码在 `drivers/input/input.c`。它的主要职责是管理所有输入设备和事件处理器（Handler），当驱动报告事件时，Input Core 负责把事件分发给所有注册的 Handler。

我们来看一下核心的事件报告函数 `input_event()`：

```c
void input_event(struct input_dev *dev,
                 unsigned int type, unsigned int code, int value)
{
    if (is_event_supported(type, dev->evbit, EV_MAX)) {
        guard(spinlock_irqsave)(&dev->event_lock);
        input_handle_event(dev, type, code, value);
    }
}
EXPORT_SYMBOL(input_event);
```

这个函数看似简单，实际上做了不少事情。首先是检查设备是否支持该事件类型，`is_event_supported()` 会检查设备的 `evbit` 位图。如果你设置设备只支持 `EV_KEY`，但报告了 `EV_ABS` 事件，这个函数会忽略你的报告。

::: tip
事件类型检查的目的是防止驱动报告不合理的事件。如果 Handler 不处理某类事件，提前忽略可以减少不必要的处理。
:::

如果事件类型有效，接下来是获取自旋锁并调用 `input_handle_event()`。这里的 `guard()` 是内核的新特性，它会在作用域结束时自动释放锁，比传统的 `spin_lock_irqsave()` / `spin_unlock_irqrestore()` 更安全，不会忘记解锁。

`input_handle_event()` 会做进一步的处理，比如把事件放入缓冲区、唤醒等待的进程等。对于按键事件，它还会处理自动重复（autorepeat）逻辑——如果你按住按键不放，系统会自动产生重复按键事件。

## Handler：事件到用户空间的桥梁

Handler 是 Input 子系统中负责与用户空间交互的组件。当 Input Core 分发事件时，所有注册的 Handler 都会收到这个事件。每个 Handler 可以决定如何处理这个事件：有的传递给用户空间，有的转发到其他子系统。

最常见的 Handler 是 evdev，代码在 `drivers/input/evdev.c`。它的作用是创建 `/dev/input/eventX` 设备节点，让用户空间程序可以通过标准的 read()/poll()/select() 接口读取输入事件。

::: info
"evdev" 这个名字可能让人困惑——它不是"event device"的缩写，而是"evdev"（通用事件设备）。历史原因是这个名字很早就定了，后来就一直沿用。
:::

除了 evdev，还有其他 Handler：

- **kbd Handler**：把键盘事件转发到虚拟终端（TTY）
- **joydev Handler**：处理游戏手柄设备，创建 `/dev/input/jsX`
- **mousedev Handler**：把鼠标事件转换成传统鼠标接口，创建 `/dev/input/mouseX`

每个 Handler 在系统启动时注册自己，当新的输入设备注册时，Handler 会判断是否要处理这个设备。判断的标准通常是设备支持的事件类型——如果设备支持 `EV_KEY`，evdev 和 kbd 都可能会注册。

## 驱动层：我们的代码在哪儿

驱动层就是我们要写的代码。驱动的工作流程可以概括为三个步骤：分配 input_dev、配置设备能力、注册到 Input 子系统。

```c
/* 分配 input_dev */
dev->input_dev = input_allocate_device();
if (!dev->input_dev) {
    return -ENOMEM;
}
```

`input_allocate_device()` 分配并初始化一个 `input_dev` 结构体。这里有个容易踩坑的点：分配失败返回的是 NULL 而不是 ERR_PTR，所以判断时要用 `if (!dev)` 而不是 `if (IS_ERR(dev))`。说实话，这个不一致性让不少新手踩过坑。

```c
/* 配置设备基本信息 */
dev->input_dev->name = "imxaes-key";
dev->input_dev->phys = "imxaes-key/input0";
dev->input_dev->id.bustype = BUS_HOST;
dev->input_dev->id.vendor = 0x0001;
dev->input_dev->id.product = 0x0001;
dev->input_dev->id.version = 0x0100;
```

这里设置了设备的名称和 ID 信息。`name` 会出现在 `/proc/bus/input/devices` 中，应该用一个有意义的名字。`phys` 是设备的物理路径，对于 USB 设备可能是 "usb-0000:00:14.0-1/input0"，对于我们的 GPIO 按键就用一个假路径就好。

`struct input_id` 包含四个字段，用来标识设备：

```c
struct input_id {
    __u16 bustype;   /* 总线类型 */
    __u16 vendor;    /* 厂商 ID */
    __u16 product;   /* 产品 ID */
    __u16 version;   /* 版本号 */
};
```

`bustype` 表示设备连接的总线类型，常见值有：
- `BUS_HOST`：集成在主板上的设备（如 GPIO 按键）
- `BUS_USB`：USB 设备
- `BUS_I2C`：I2C 设备
- `BUS_SPI`：SPI 设备

对于我们的 GPIO 按键，用 `BUS_HOST` 就对了。

vendor、product、version 是厂商和产品信息。对于真正的硬件产品，这些应该用正确的值；对于教程代码，用 0x0001 这样的占位值就好。

::: tip
设备 ID 的主要用途是让用户空间程序识别设备。比如 X11 可以根据 vendor/product 应用特定的配置，游戏手柄驱动可以根据这些 ID 匹配特定的硬件配置。
:::

## 设置设备能力

这是最关键的一步——告诉 Input 子系统这个设备能做什么：

```c
/* 设置支持按键事件 */
set_bit(EV_KEY, dev->input_dev->evbit);

/* 设置支持 Enter 键 */
set_bit(KEY_ENTER, dev->input_dev->keybit);
```

`set_bit()` 是一个位操作宏，把位图的指定位设置为 1。`evbit` 是事件类型位图，`keybit` 是按键代码位图。这样设置后，Input Core 就知道这个设备支持 `EV_KEY` 类型的 `KEY_ENTER` 事件。

如果想支持多个按键，就多调用几次 `set_bit()`：

```c
set_bit(EV_KEY, dev->input_dev->evbit);
set_bit(KEY_ENTER, dev->input_dev->keybit);
set_bit(KEY_ESC, dev->input_dev->keybit);
set_bit(KEY_1, dev->input_dev->keybit);
```

::: info
Input 子系统支持很多事件类型：`EV_KEY`（按键）、`EV_REL`（相对坐标，鼠标移动）、`EV_ABS`（绝对坐标，触摸屏）、`EV_MSC`（其他事件）、`EV_LED`（LED 状态）、`EV_REP`（自动重复）等。不同事件类型对应不同的位图。
:::

## 注册设备

配置完成后，就可以注册到 Input 子系统：

```c
ret = input_register_device(dev->input_dev);
if (ret) {
    pr_err("Failed to register input device: %d\n", ret);
    goto err_free_input_dev;
}
```

`input_register_device()` 会做几件事：把设备添加到 Input Core 的设备列表，通知所有 Handler 有新设备到来，让 Handler 决定是否要处理这个设备。对于 evdev Handler，它会创建 `/dev/input/eventX` 设备节点。

::: warning
注册失败的情况通常是资源不足或者参数错误。常见错误包括忘记设置 `evbit`、设备名称为 NULL 等。注册失败后必须调用 `input_free_device()` 释放资源。
:::

## 设备节点的创建

注册成功后，evdev Handler 会自动创建设备节点。你可以通过几种方式找到你的设备：

```bash
# 方法 1：查看 /proc/bus/input/devices
cat /proc/bus/input/devices

# 方法 2：在 sysfs 中查找
grep -r "imxaes-key" /sys/class/input/input*/name
```

`/proc/bus/input/devices` 包含所有输入设备的详细信息：

```
I: Bus=0019 Vendor=0001 Product=0001 Version=0100
N: Name="imxaes-key"
P: Phys=imxaes-key/input0
S: Sysfs=/devices/platform/imxaes-key/input/input0
U: Uniq=
H: Handlers=event0
B: PROP=0
B: EV=3
B: KEY=100000 0 0 0
```

这里的 `Handlers=event0` 表示这个设备对应 `/dev/input/event0`。`EV=3` 表示支持 `EV_KEY`（事件类型 1 + EV_REL（2）= 3），`KEY` 行是支持的按键代码位图。

## 清理资源

卸载驱动时，需要按相反顺序清理资源：

```c
static void input_key_remove(struct platform_device *pdev)
{
    struct input_key_dev *dev = platform_get_drvdata(pdev);

    if (dev) {
        /* 取消消抖工作 */
        cancel_delayed_work_sync(&dev->debounce_work);

        /* 注销 input 设备 */
        input_unregister_device(dev->input_dev);

        /* 清理 GPIO 资源 */
        key_hw_deinit(dev->gpio);

        /* 释放设备结构 */
        kfree(dev);
    }
}
```

`input_unregister_device()` 会做三件事：从 Input Core 移除设备，通知所有 Handler，Handler 会删除对应的设备节点。注意这里用的是 `input_unregister_device()` 而不是 `input_free_device()`，区别是前者会通知 Handler，后者只是释放内存。

::: tip
清理顺序很重要：先取消延时工作，再注销设备。如果顺序反了，可能在设备注销后工作队列还在运行，访问已释放的内存导致内核 panic。
:::

## 内核源码的位置

如果你想深入研究 Input 子系统的实现，主要源码文件在：

```
drivers/input/
├── input.c           # Input Core
├── evdev.c           # evdev Handler
├── keyboard/         # kbd Handler
├── mouse/            # mousedev Handler
├── joystick/         # joydev Handler
└── misc/             # 其他 Handler
```

头文件在 `include/linux/input.h` 和 `include/uapi/linux/input-event-codes.h`。

## 本章小结

Input 子系统的分层架构可以总结为三部分：驱动层报告事件，Input Core 分发事件，Handler 把事件传递给用户空间。驱动开发的核心流程是：分配 input_dev、配置设备能力（`evbit`/`keybit`）、注册到子系统。注册成功后，evdev Handler 自动创建 `/dev/input/eventX` 设备节点。

理解这个架构很重要，因为它决定了你的代码应该怎么写。驱动不需要关心设备节点怎么创建、事件怎么传递给用户空间，这些由子系统的其他层负责。你只需要做两件事：正确配置设备能力，正确报告事件。

---

**下一步：** 继续阅读 [03_event_reporting.md](03_event_reporting.md) 了解事件报告的具体实现。
