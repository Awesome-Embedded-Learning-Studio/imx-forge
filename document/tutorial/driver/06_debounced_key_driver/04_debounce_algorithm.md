# 消抖算法 - 延时读取是关键

前面几章我们讲了中断子系统和工作队列机制，现在终于可以开始实现真正的消抖算法了。说实话，这个算法的原理非常简单，但实现细节上有很多需要注意的地方。

## 消抖的核心思想

消抖的核心思想就一句话：**等待抖动结束后再读取 GPIO**。

机械按键在按下或松开的瞬间，触点会有一段时间的抖动。如果我们在这个抖动期读取 GPIO，可能会读到错误的值。更糟糕的是，抖动会触发多次中断，导致应用程序收到一堆无意义的事件。

解决方法是：当中断触发时，我们不立即读取 GPIO，而是等一段时间（比如 20ms），让抖动自然结束，然后再读取。这时候读到的值就是稳定的按键状态。

```c
// 工作队列处理函数
static void key_work_handler(struct work_struct* work) {
    msleep_interruptible(DEBOUNCE_MS);  // 等待抖动结束
    int state = key_get_state(gpio);     // 读取稳定的状态
    // 报告事件...
}
```

::: tip 20ms 从哪来
20ms 是一个经验值，大部分机械按键的抖动期在 5-20ms 之间。你可以根据实际按键的特性调整这个值。太短可能消抖不干净，太长会影响响应速度。
:::

## 工作处理函数的完整实现

让我们看一下完整的工作处理函数：

```c
static void key_work_handler(struct work_struct* work)
{
    struct key_debounce_dev* dev =
        container_of(work, struct key_debounce_dev, work);
    int current_state;
    unsigned long flags;

    /* 消抖延时 - 等待机械抖动稳定 */
    msleep_interruptible(DEBOUNCE_MS);

    /* 读取稳定的 GPIO 状态：0=按下，1=松开 */
    current_state = key_get_state(dev->gpio);

    spin_lock_irqsave(&dev->lock, flags);

    /* 只有状态真的变了才生成事件 */
    if (current_state != dev->last_gpio_state) {
        dev->last_gpio_state = current_state;
        /* 返回应用层约定：1=按下，0=松开 */
        dev->key_value = !current_state;
        dev->event_ready = true;
        wake_up_interruptible(&dev->waitq);
        atomic_inc(&dev->event_count);
    } else {
        /* 状态没变，跳过这次事件（抖动） */
        atomic_inc(&dev->debounce_skipped);
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}
```

这个函数是整个驱动最核心的部分，让我们一步步拆解。

## 步骤一：延时等待抖动结束

```c
msleep_interruptible(DEBOUNCE_MS);
```

`DEBOUNCE_MS` 在我们的驱动里定义为 20ms。这个延时是消抖的关键。

你可能会问：为什么不用 `usleep()` 或者 `ndelay()`？因为按键抖动是毫秒级别的，用 `msleep()` 就够了。`usleep()` 或 `ndelay()` 提供的微秒级精度在这里没有意义，反而增加了不必要的开销。

::: info msleep_interruptible 的选择
我们用 `msleep_interruptible()` 而不是 `msleep()`，因为前者可以被信号中断。这对于用户交互的设备是个好特性——用户按 Ctrl+C 时，工作队列能快速响应。
:::

## 步骤二：读取 GPIO 状态

```c
current_state = key_get_state(dev->gpio);
```

延时之后，我们读取 GPIO 状态。这时候按键应该已经稳定了，读到的就是真实的状态。

`key_get_state()` 是一个简单的封装函数：

```c
static int key_get_state(struct gpio_desc* gpio)
{
    return gpiod_get_value(gpio);  // 0=按下，1=松开
}
```

这里有个约定：GPIO 返回 0 表示按下，1 表示松开。这是硬件决定的（按键连接到 GND）。但用户空间的约定通常是 1 表示按下，0 表示松开，所以我们在后面做了转换。

## 步骤三：比较状态变化

```c
if (current_state != dev->last_gpio_state) {
    // 状态真的变了，报告事件
} else {
    // 状态没变，这是抖动，跳过
}
```

这是消抖算法的核心逻辑。我们不是无条件地报告事件，而是比较当前状态和上一次状态。只有状态真的变化了，才报告事件。

为什么要这样？考虑这个场景：

```
t=0ms:   按键按下，GPIO 从 1 变成 0，中断触发
t=0ms:   工作队列调度，开始延时
t=5ms:  抖动，GPIO 从 0 变成 1，中断触发
t=5ms:   工作队列重新调度，开始延时
t=10ms: 抖动，GPIO 从 1 变成 0，中断触发
t=10ms:  工作队列重新调度，开始延时
t=20ms: 延时结束，读取 GPIO = 0（按下）
```

如果没有 `last_gpio_state` 比较，我们会报告多次按下事件。但有了这个比较，我们可以看到：
- 第一次工作队列执行：`current_state=0` ≠ `last_gpio_state=1`，报告事件
- 第二次工作队列执行：`current_state=0` = `last_gpio_state=0`，跳过（抖动）

::: tip 状态比较的妙处
这个状态比较不仅过滤了抖动，还自然地实现了"边沿检测"。只有当 GPIO 状态真正变化时才报告事件，而不是每次中断都报告。这比单纯延时更可靠。
:::

## 步骤四：更新状态和唤醒等待队列

```c
dev->last_gpio_state = current_state;
dev->key_value = !current_state;  // 转换约定：1=按下，0=松开
dev->event_ready = true;
wake_up_interruptible(&dev->waitq);
atomic_inc(&dev->event_count);
```

如果状态真的变化了，我们做这些事情：
1. 更新 `last_gpio_state`，下次比较用
2. 转换约定：硬件 0=按下，软件 1=按下
3. 设置 `event_ready` 标志
4. 唤醒等待队列（如果有进程在等待）
5. 递增事件计数器

`key_value` 的转换是因为硬件和软件的约定不同。硬件上，按键按下时 GPIO 为 0（连接到 GND）。但在软件层面，我们通常用 1 表示按下，0 表示松开。所以这里做了取反操作。

## 步骤五：统计抖动次数

```c
} else {
    /* 状态没变，这是抖动，跳过 */
    atomic_inc(&dev->debounce_skipped);
}
```

如果状态没有变化，我们递增 `debounce_skipped` 计数器。这个计数器可以帮助我们验证消抖效果。如果 `debounce_skipped` 很高，说明消抖在工作，成功过滤了很多抖动。

::: tip 统计信息的作用
驱动维护了三个计数器：
- `irq_count`：中断触发次数
- `event_count`：实际事件次数
- `debounce_skipped`：被过滤的抖动次数

正常情况下，`event_count << irq_count`，`debounce_skipped` 应该比较高。这能证明消抖在有效工作。
:::

## 完整的时序图

让我们看一个完整的时序，假设用户按下按键：

```
时间    GPIO状态   中断   工作队列          动作
------------------------------------------------------------
t=0     1→0        ✓     调度              开始延时20ms
t=1     0→1        ✓     重新调度           延时重置，再等20ms
t=2     1→0        ✓     重新调度           延时重置，再等20ms
t=3     0          -     (仍在延时)        ...
t=5     0          -     (仍在延时)        ...
t=22    0          -     执行              读取GPIO=0
                                                last_state=1
                                                状态变化→报告事件
                                                last_state更新为0
```

注意 t=1ms 和 t=2ms 的抖动会触发新的中断，新的中断会重新调度工作队列，重置延时。最终工作队列在 t=22ms 执行，此时 GPIO 已经稳定在 0，状态从上次的 1 变成了 0，所以报告按下事件。

## 为什么用 schedule_work 而不是 schedule_delayed_work

你可能会问，为什么不直接用 `schedule_delayed_work()` 延时调度，而是立即调度然后在工作函数里 `msleep()`？

```c
// 方式一：立即调度 + 工作函数里延时
schedule_work(&dev->work);
// 工作函数里：msleep(20);

// 方式二：延时调度
schedule_delayed_work(&dev->work, msecs_to_jiffies(20));
```

两种方式都能实现 20ms 延时，但第一种方式有个好处：每次中断触发都会重新调度工作队列，重置延时。这对于消抖是个很好的特性——如果抖动持续触发中断，延时会被不断重置，直到抖动真正结束。

::: tip 工作队列的重调度
`schedule_work()` 可以重复调用，如果工作已经在队列里，会被移动到队列末尾（相当于重置延时）。这个特性对于消抖很有用。
:::

## 本章小结

消抖算法的核心是延时读取 + 状态比较。中断触发时不立即读取，而是调度工作队列，等 20ms 后再读取稳定的 GPIO 状态。只有当前状态和上一次状态不同时，才报告事件。

这个算法简单但有效。它利用了工作队列的重调度特性——抖动期间的每个中断都会重新调度工作队列，重置延时。最终工作队列执行时，抖动早已结束，读到的就是稳定的按键状态。

状态比较的加入使得算法更加可靠。即使工作队列多次执行，只有状态真正变化时才报告事件。这有效地过滤了所有抖动，只保留真实的按键事件。

下一章我们会讲同步机制，看看为什么需要自旋锁和等待队列，它们是如何保证多线程安全的。

---

**相关文档**：
- [工作队列机制](03_work_queue.md)
- [同步机制详解](05_synchronization.md)
