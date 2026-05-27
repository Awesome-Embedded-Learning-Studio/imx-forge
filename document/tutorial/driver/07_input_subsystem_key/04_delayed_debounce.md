# 延时消抖 - 跟按键抖动说再见

前面我们讲过中断和工作队列，说过按键需要消抖。之前的教程用普通的 `work_struct` 加定时器来实现，这一章我们来学一种更优雅的方案——`delayed_work`。说实话，第一次看到这个机制的时候，我觉得它就是为按键消抖而生的。

## 为什么需要消抖

你可能会问：按键按下就是按下，为什么要消抖？这是一个好问题。现实中的机械按键并不是理想的开关，按下时触点会有一段不稳定期：

```
物理电平（理想）:
按下 ────────────────────────
松开   ──────────────────────

物理电平（真实）:
按下 ═══╦═╗╔═╝╚═╗╔══════════
松开   ───╩═╝╚═╗╔═╝╚─────────
           ↑抖动期↑
```

在抖动期间，GPIO 电平会在 0 和 1 之间快速跳变。如果不消抖，一次按键会被识别成多次按下和松开。如果在中断处理函数里直接报告事件，用户空间可能会收到一连串的按下/松开事件，按键完全没法用。

::: info
消抖的原理很简单：等待抖动期过去（通常 10-50ms），再读取 GPIO 状态。如果状态稳定，才认为是一次真实的按键动作。
:::

## delayed_work vs work_struct

之前的教程我们用过 `schedule_work()` 调度一个 `work_struct`。但 `work_struct` 本身不支持延时，必须配合定时器使用。而 `delayed_work` 是内核提供的一个封装，内置了延时支持。

| 特性 | work_struct | delayed_work |
|------|-------------|--------------|
| 延时执行 | 需要 timer | 内置 |
| 重新调度 | cancel + schedule | `mod_delayed_work()` |
| 适用场景 | 立即执行的任务 | 需要延时或重新调度的任务 |

对于消抖这种场景，`delayed_work` 有一个巨大的优势：可以"重新调度"。当按键抖动触发多次中断时，我们可以不断重新调度延时工作，每次都重置计时器。只有最后一次中断后，经过完整的消抖时间，工作函数才会执行。

## 中断处理函数：重新调度的艺术

来看一下中断处理函数的实现：

```c
static irqreturn_t input_key_irq_handler(int irq, void *dev_id)
{
    struct input_key_dev *dev = dev_id;

    /* 重新调度延时工作（取消 pending 并重启计时） */
    mod_delayed_work(system_wq, &dev->debounce_work,
                     msecs_to_jiffies(DEBOUNCE_MS));

    return IRQ_HANDLED;
}
```

`mod_delayed_work()` 是关键函数。它的作用是：
1. 如果工作已经在队列中，先取消
2. 重新调度，延时指定时间后执行

::: tip
`mod_delayed_work()` 的"重新调度"特性完美匹配消抖场景。每次抖动触发中断，我们就重新开始计时。只有当抖动完全停止，工作函数才会执行。
:::

假设消抖时间是 20ms，按键按下后发生了抖动：

```
t=0ms:   按下 → 中断 → 调度 20ms 延时工作
t=5ms:   抖动 → 中断 → 重新调度 20ms 延时工作（计时重置）
t=10ms:  抖动 → 中断 → 重新调度 20ms 延时工作（计时重置）
t=12ms:  抖动 → 中断 → 重新调度 20ms 延时工作（计时重置）
t=32ms:  工作函数执行（从最后一次中断起 20ms）
```

最后一次抖动在 t=12ms，工作函数在 t=32ms 执行，刚好是 20ms 后。这时候电平已经稳定，读取到的状态就是正确的。

::: info
如果用普通 work_struct + timer，每次中断都要 cancel timer + restart timer，代码会更复杂。`mod_delayed_work()` 一步到位。
:::

## 工作函数：状态变化检测

延时工作到期后，工作函数执行。它的职责是读取 GPIO 状态，如果状态确实改变了，就报告事件：

```c
static void debounce_work_handler(struct work_struct *work)
{
    struct delayed_work *dwork = to_delayed_work(work);
    struct input_key_dev *dev = container_of(dwork,
                                             struct input_key_dev,
                                             debounce_work);
    int current_state;
    unsigned long flags;

    /* 读取 GPIO 逻辑状态 */
    current_state = key_hw_get_raw_state(dev->gpio);

    spin_lock_irqsave(&dev->lock, flags);

    /* 只有状态变化才报告事件 */
    if (current_state != dev->last_state) {
        dev->last_state = current_state;

        input_report_key(dev->input_dev, KEY_ENTER, current_state);
        input_sync(dev->input_dev);

        pr_debug("input_key_work: key %s\n",
                 current_state ? "pressed" : "released");
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}
```

这里有几个重要细节。首先是 `to_delayed_work()`，它从 `work_struct*` 获取 `delayed_work*`，因为 `delayed_work` 内部包含一个 `work_struct`。

然后是 `container_of()`，从 `delayed_work*` 获取我们的设备结构体。这是内核编程的标准模式，屡见不鲜。

最关键的是状态变化检测：只有 `current_state != last_state` 才报告事件。这是为了防止重复报告。假设按键按住不放，GPIO 状态一直是 1，每次中断重新调度工作，但状态没变，就不会重复报告"按下"事件。

::: warning
状态检测必须用自旋锁保护。中断处理函数可能会同时访问 `last_state`，虽然对于按键这种竞态可能不会造成大问题，但正确做法还是加锁。
:::

## 初始化 delayed_work

在 probe 函数中初始化 `delayed_work`：

```c
/* 初始化延时工作 */
INIT_DELAYED_WORK(&dev->debounce_work, debounce_work_handler);
```

`INIT_DELAYED_WORK()` 设置工作函数和关联的 `delayed_work` 结构体。初始化后，工作还没有被调度，需要在中断发生时第一次调度。

::: info
在新的内核版本（5.9+）中，`INIT_DELAYED_WORK` 被废弃，推荐使用 `INIT_DEFERRABLE_WORK` 或直接初始化 `work` 和 `timer` 字段。但很多驱动还在用旧 API，为了兼容性教程继续使用它。
:::

## 卸载时取消工作

驱动卸载时，必须确保延时工作被取消：

```c
static void input_key_remove(struct platform_device *pdev)
{
    struct input_key_dev *dev = platform_get_drvdata(pdev);

    if (dev) {
        /* 取消延时工作 */
        cancel_delayed_work_sync(&dev->debounce_work);

        /* 注销 input 设备 */
        input_unregister_device(dev->input_dev);

        /* 释放 GPIO 资源 */
        key_hw_deinit(dev->gpio);

        /* 释放设备结构 */
        kfree(dev);
    }
}
```

`cancel_delayed_work_sync()` 会：
1. 如果工作还在队列中，取消它
2. 如果工作正在执行，等待它完成

::: warning
必须用 `_sync` 版本，不能只用 `cancel_delayed_work()`。如果工作正在执行 `input_report_key()`，而你注销了 `input_dev`，就会访问已释放的内存，内核 panic。
:::

## 消抖时间的选择

消抖时间选多少合适？一般来说：

- **机械按键**：10-50ms
- **薄膜按键**：20-100ms
- **电容触摸按键**：50-200ms

我们的驱动用 20ms：

```c
#define DEBOUNCE_MS 20
```

这个值对大多数机械按键都够用了。如果你发现按键还是有抖动，可以增加到 30ms 或 50ms。但也不是越大越好，太大会让按键响应变慢，用户感觉"迟钝"。

::: tip
调试消抖时间时，可以在工作函数里加 `pr_info()` 打印时间戳，观察实际消抖延迟。用 `dmesg | grep input_key` 查看。
:::

## 为什么不用硬件消抖

有些硬件支持硬件消抖，通过配置寄存器让 GPIO 控制器自动过滤抖动。但我们的教程用软件消抖，原因是：

1. **通用性**：不是所有平台都支持硬件消抖
2. **灵活性**：软件消抖可以根据应用调整时间
3. **教学目的**：软件消抖是内核驱动编程的常见模式

如果你的平台支持硬件消抖，可以优先使用，能减少 CPU 占用。

## 与字符设备驱动的消抖对比

之前的字符设备驱动也用了 `work_struct` 消抖，但实现方式不同：

```c
/* 字符设备驱动 */
static irqreturn_t key_irq_handler(int irq, void *dev_id)
{
    struct key_dev *dev = dev_id;

    schedule_work(&dev->work);
    return IRQ_HANDLED;
}
```

这种实现没有重新调度机制，每次抖动都会触发一次工作函数执行，只是在工作函数里加了延时。而 `delayed_work` 的重新调度机制更高效，抖动期间只执行一次工作函数。

::: info
对于高频抖动，`delayed_work` 优势更明显。每次中断只是更新定时器，而不是执行完整的工作函数，减少了 CPU 占用。
:::

## 本章小结

`delayed_work` 是实现消抖的优雅方案。中断处理函数用 `mod_delayed_work()` 重新调度延时工作，每次抖动重置计时器。只有当抖动完全停止，工作函数才会执行。工作函数检测状态变化，只有状态真正改变才报告事件。

卸载驱动时必须用 `cancel_delayed_work_sync()` 等待工作完成，防止访问已释放的内存。消抖时间通常选 20ms，可以根据实际按键特性调整。

下一章我们会讲解如何与用户空间集成，编写应用程序读取按键事件。

---

**相关文档**：
- [中断消抖按键](../06_debounced_key_driver/) - 中断与工作队列基础
- [事件报告](03_event_reporting.md) - Input 事件报告机制

**下一步：** 继续阅读 [05_userspace_integration.md](05_userspace_integration.md) 了解用户空间集成。
