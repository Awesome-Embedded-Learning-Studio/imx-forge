# 中断子系统 - 硬件和软件的桥梁

上一章我们讲了为什么要用中断方式，现在我们具体看看 Linux 的中断子系统是怎么工作的。说实话，中断这个概念在操作系统里挺复杂的，但在驱动开发层面，我们需要掌握的核心 API 其实不多。把这几个 API 用熟了，大部分中断相关的驱动都能搞定。

## 中断是什么

先从最基础的概念说起。中断是硬件通知 CPU 的一种机制。当某个硬件事件发生时（比如按键按下、数据到达、DMA 完成），硬件会产生一个中断信号。CPU 收到这个信号后，会暂停当前正在执行的任务，跳转到中断处理函数执行。处理完之后，再回到原来的任务继续执行。

你可以把它想象成一个插队机制。CPU 正在按顺序处理各种任务，突然一个硬件说"我有急事"，CPU 就停下来去处理这个急事。处理完了，再回来继续之前的任务。

::: tip 为什么叫"中断"
因为 CPU 正在执行的程序被"打断"了。这个概念最早来自硬件设计，CPU 的指令执行流程被外部信号中断。
:::

## GPIO 中断配置

在 i.MX 系列处理器上，GPIO 可以配置成中断源。我们需要配置两件事：触发方式和中断处理函数。

触发方式指的是在什么条件下触发中断：

```c
#define IRQF_TRIGGER_RISING    0x00000001  // 上升沿触发
#define IRQF_TRIGGER_FALLING   0x00000002  // 下降沿触发
#define IRQF_TRIGGER_HIGH      0x00000004  // 高电平触发
#define IRQF_TRIGGER_LOW       0x00000008  // 低电平触发
```

对于按键这种设备，我们通常用边沿触发，因为按键状态变化是我们关心的。上升沿对应按键松开（如果硬件设计是松开为高电平），下降沿对应按键按下。

我们的驱动用双边沿触发，这样按键按下和松开都能检测：

```c
unsigned long irq_flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;
```

::: info 电平触发 vs 边沿触发
电平触发适合那些需要持续监控的信号，比如外部设备的"忙"信号。边沿触发适合状态变化事件，比如按键、传感器信号。对于按键，边沿触发是更好的选择，因为我们只关心状态变化的那一刻。
:::

## 从 GPIO 到中断号

GPIO 子系统和中断子系统是紧密集成的。我们可以通过 GPIO 描述符获取对应的中断号：

```c
int irq = gpiod_to_irq(gpio);
if (irq < 0) {
    pr_err("Failed to get IRQ for GPIO: %d\n", irq);
    return irq;
}
```

`gpiod_to_irq()` 这个函数会在 GPIO 的 irqchip 里查找对应的中断号。如果成功，返回一个正整数（中断号）；如果失败，返回一个负的错误码。

说实话，这个函数的名字可能会让人困惑。它不是真的"转换"什么东西，而是查找 GPIO 对应的中断号。在硬件层面，每个 GPIO（或者一组 GPIO）都对应一个中断线，这个函数就是找出那个中断线的编号。

## 注册中断处理函数

拿到中断号之后，我们就可以注册中断处理函数了：

```c
ret = devm_request_irq(dev, irq, key_irq_handler, irq_flags,
                       "imxaes_key_debounce", dev);
if (ret < 0) {
    pr_err("Failed to request IRQ %d: %d\n", irq, ret);
    return ret;
}
```

我们用的是 `devm_request_irq()`，这是 `request_irq()` 的托管版本。`devm_` 前缀代表"managed resource"，当设备卸载时，内核会自动释放这个中断。不用 `devm_` 版本的话，你得在 `remove` 函数里手动调用 `free_irq()`，很容易忘。

参数说明：
- `dev`：设备指针，用于资源管理
- `irq`：中断号，就是我们刚才用 `gpiod_to_irq()` 获取的
- `key_irq_handler`：中断处理函数指针
- `irq_flags`：中断标志，包括触发方式
- `"imxaes_key_debounce"`：中断名称，会出现在 `/proc/interrupts` 里
- `dev`：传递给中断处理函数的私有数据

::: tip 查看中断统计
你可以通过 `/proc/interrupts` 文件查看系统中断的统计信息：
```bash
cat /proc/interrupts | grep imxaes
```
这会显示你的驱动触发了多少次中断，调试时很有用。
:::

## 中断处理函数

中断处理函数是整个中断机制的核心。它的签名是固定的：

```c
static irqreturn_t key_irq_handler(int irq, void *dev_id)
{
    struct key_debounce_dev* dev = dev_id;

    /* 递增中断计数器 */
    atomic_inc(&dev->irq_count);

    /* 调度工作队列进行消抖处理 */
    schedule_work(&dev->work);

    return IRQ_HANDLED;
}
```

这个函数的第一个参数是中断号，第二个参数是我们在注册时传递的私有数据（`dev`）。返回值是 `irqreturn_t` 类型，有两个可能的值：

```c
typedef enum irqreturn {
    IRQ_NONE        = 0,    // 不是这个设备的中断
    IRQ_HANDLED     = 1,    // 已处理
} irqreturn_t;
```

::: warning 中断处理函数的约束
中断处理函数运行在中断上下文，有很多约束：
1. 不能睡眠（不能调用 msleep、mutex_lock 等）
2. 不能调用可能睡眠的函数
3. 必须快速执行（通常不超过几微秒）
4. 不能访问用户空间内存

违反这些约束会导致内核 panic 或系统死锁。
:::

## 中断共享

Linux 支持中断共享，多个设备可以共享同一个中断线。这就是为什么中断处理函数需要返回值——如果返回 `IRQ_NONE`，内核会把中断传给下一个共享这个中断的处理器。

在注册共享中断时，需要设置 `IRQF_SHARED` 标志：

```c
request_irq(irq, handler, IRQF_SHARED, "name", dev);
```

共享中断时，所有注册的处理器都会被调用，每个处理器需要判断是否是自己的中断。如果不是，返回 `IRQ_NONE`。

::: tip 实际经验
GPIO 中断通常不需要共享，因为每个 GPIO 有自己独立的中断号。但在 PCI 设备中，中断共享很常见，因为多个设备可能连接到同一个 IRQ 引脚。
:::

## 中断处理的时机

你可能会问，中断处理函数什么时候被调用？是在中断触发后立即调用吗？

答案是：几乎立即。中断触发后，CPU 会完成当前指令，然后保存当前状态，跳转到中断处理函数。这个过程通常在几微秒内完成。

但要注意的是，中断处理函数运行在中断上下文，而不是进程上下文。这意味着：
- 它没有进程控制块（没有 `current` 指针）
- 它不能被调度（不能睡眠）
- 它运行在高优先级，会打断普通进程

## 内核的中断管理

在内核内部，中断管理比我们看到的要复杂得多。`request_irq()` 最终会调用到中断核心代码，在 `/kernel/irq/manage.c` 里：

```c
int request_threaded_irq(unsigned int irq, irq_handler_t handler,
                         irq_handler_t thread_fn, unsigned long irqflags,
                         const char *devname, void *dev_id)
{
    /* 分配 irq_desc 结构 */
    /* 设置 handler 和 thread_fn */
    /* 启用中断线 */
    /* ... */
}
```

内核维护了一个 `irq_desc` 数组，每个中断号对应一个 `irq_desc`。这个结构体包含了中断的所有信息：处理函数、状态、锁等。当硬件触发中断时，内核会查找对应的 `irq_desc`，调用注册的处理函数。

## 顶半部和底半部

你可能会听到"顶半部"（top half）和"底半部"（bottom half）这两个词。这是 Linux 中断处理的一种设计模式。

顶半部就是中断处理函数本身，必须快速执行，不能睡眠。底半部可以推迟执行，可以睡眠，可以做耗时操作。

我们的驱动就是典型的顶半部/底半部分离：
- 顶半部：中断处理函数，只是调度一个工作队列
- 底半部：工作队列处理函数，延时读取 GPIO，报告事件

```c
// 顶半部（中断处理函数）
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    schedule_work(&dev->work);  // 只是调度，立即返回
    return IRQ_HANDLED;
}

// 底半部（工作队列处理函数）
static void key_work_handler(struct work_struct *work) {
    msleep(20);  // 可以睡眠！
    // 做实际的处理...
}
```

::: tip 什么时候需要底半部
如果你的中断处理需要做以下事情之一，就需要底半部：
1. 耗时操作（超过几十微秒）
2. 需要睡眠（比如等待互斥锁）
3. 需要访问可能睡眠的 API

对于按键这种低速设备，几乎总是需要底半部的。
:::

## 中断的调试技巧

中断相关的问题有时候很难调试，因为涉及到硬件和时序。这里有几个实用的技巧：

1. **查看中断统计**：
```bash
cat /proc/interrupts
```
这会显示每个中断线的触发次数，可以用来验证中断是否真的触发了。

2. **打印调试**：
在中断处理函数里加个打印：
```c
pr_info("IRQ %d triggered\n", irq);
```
但要注意，打印操作本身很慢，不要在生产代码里保留。

3. **ftrace 追踪**：
内核的 ftrace 可以追踪中断的延迟：
```bash
echo 1 > /sys/kernel/debug/tracing/events/irq/enable
cat /sys/kernel/debug/tracing/trace
```

::: warning 调试中断的坑
别在中断处理函数里加太多打印，这会让系统变慢甚至死锁。中断处理函数必须快速返回，打印操作可能需要几十微秒，对于高频中断来说是不可接受的。
:::

## 本章小结

这一章我们深入了解了 Linux 的中断子系统。核心 API 其实就两个：`gpiod_to_irq()` 获取中断号，`devm_request_irq()` 注册中断处理函数。中断处理函数必须快速返回，不能睡眠，所以我们需要用工作队列来实现底半部，做实际的处理。

中断机制是操作系统里的经典设计，它解决了硬件事件如何及时通知 CPU 的问题。Linux 的中断子系统经过了多年演进，既保证了性能，又提供了简洁的 API。理解这个机制，对于编写高效的驱动程序至关重要。

下一章我们会详细讲工作队列机制，看看为什么中断里不能睡眠，以及如何安全地推迟执行。

---

**相关文档**：
- [工作队列机制](03_work_queue.md)
- [消抖算法实现](04_debounce_algorithm.md)
