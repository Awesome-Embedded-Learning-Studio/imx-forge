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
工作队列处理函数运行在内核线程（`kworker`）上下文里，它不是用户进程，收不到用户按 Ctrl+C 产生的信号，所以这里的 `msleep_interruptible()` 实际上几乎永远不会被信号打断，行为接近 `msleep()`。两者真正的区别在睡眠状态：`msleep()` 把任务置为 `TASK_UNINTERRUPTIBLE`，`msleep_interruptible()` 置为 `TASK_INTERRUPTIBLE`。这里选 `msleep_interruptible()` 主要是"能被打断就让它能被打断"的习惯写法；真正响应用户 Ctrl+C 的是 `read()` 里的 `wait_event_interruptible()`（会返回 `-ERESTARTSYS`），而不是这个工作函数。
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

为什么要这样？考虑这个场景（按下过程伴随抖动）：

```
t=0ms:   按下，GPIO 1→0，IRQ 触发，schedule_work() 成功，work 开始延时
t=5ms:   抖动，GPIO 0→1，IRQ 触发，schedule_work() 成功（见下文）
t=10ms:  抖动，GPIO 1→0，IRQ 触发，schedule_work() 失败（no-op）
...      GPIO 最终稳定在 0
t≈20ms:  第 1 次 handler 的延时结束，读 GPIO=0
t≈40ms:  第 2 次 handler 的延时结束，读 GPIO=0
```

注意：t=5ms 那次中断**并没有"重置"第 1 次延时**——它只是趁 work 正在睡眠（pending 位为空）又排了一次队，让 work 在第 1 次跑完后再跑一次。也就是说，这一次按下实际上会触发**两次** handler 执行。如果没有 `last_gpio_state` 比较，两次执行都会上报"按下"，应用层就收到重复事件。有了状态比较：
- 第 1 次 handler：`current_state=0` ≠ `last_gpio_state=1`（probe 时初始化为松开态），**报告按下事件**，并把 `last_gpio_state` 更新为 0
- 第 2 次 handler：`current_state=0` == `last_gpio_state=0`，**跳过**（`debounce_skipped` +1）

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

## 步骤五：统计"未上报"的 handler 执行

```c
} else {
    /* 状态没变，这是抖动，跳过 */
    atomic_inc(&dev->debounce_skipped);
}
```

这里要特别澄清 `debounce_skipped` 到底在数什么。它**不是**"被跳过的中断次数"，而是：**handler 真正执行到状态比较这一步后，发现 `current_state == last_gpio_state`、于是没有上报事件的次数**。

也就是说，只有当一次 work handler 完整跑完（延时 → 读 GPIO → 进临界区比较）并且走进了 `else` 分支，`debounce_skipped` 才会 +1。而那些被 `schedule_work()` 直接吞掉（返回 0、根本没排上队）的中断，既不会增加 `event_count`，也不会增加 `debounce_skipped`。

::: tip 三个计数器不是简单加减关系
驱动维护了三个计数器，统计口径互不相同：
- `irq_count`：每进入一次中断处理函数就 +1（不管这次中断最终有没有用）。
- `event_count`：每上报一次按键事件（`current_state != last_gpio_state` 那个分支）就 +1。
- `debounce_skipped`：handler 跑完但没上报事件（`else` 分支）就 +1。

不要写成 `irq_count == event_count + debounce_skipped`。因为有些中断会让 `schedule_work()` 变成 no-op（工作已在队列里），这些中断不会产生任何一次 handler 执行，自然既不算进 `event_count` 也不算进 `debounce_skipped`。实际能观察到的是 `event_count ≤ irq_count`，而 `debounce_skipped` 反映的是"handler 多跑了多少次却没产生事件"。
:::

## 完整的时序图

让我们看一个完整的时序（按下过程伴随抖动）：GPIO 在 t=0、t=5、t=10 来回跳，最终稳定在 0（按下）。

```
时间     GPIO   IRQ (irq_count)   schedule_work()    work 状态               关键动作
====================================================================================================
t≈0     1→0    IRQ1 (→1)         成功（首次排队）   IDLE → PENDING          首次调度
t≈0+ε   —      —                 —                  PENDING → RUNNING       worker 取走，清 PENDING 位
                                                                            └─ msleep(20) 开始，睡到 t≈20
t=5     0→1    IRQ2 (→2)         成功（重新排队）   RUNNING + PENDING       work 正在睡(非pending)，可再排队
                                                                            └─ 注意: 不打断、不重置当前 msleep!
t=10    1→0    IRQ3 (→3)         失败（返回 0）     RUNNING + PENDING       已 pending → schedule_work() 是 no-op
…       0      —                 —                  —                       GPIO 已稳定在 0
t≈20    0      —                 —                  ── 第 1 次 handler ──    msleep 结束
                                    读 GPIO=0; last_gpio_state=1 → 不等
                                    event_count+1(=1); last_gpio_state:=0; wake_up()    ← 真正上报"按下"
t≈20+ε  —      —                 —                  PENDING → RUNNING       第 2 次 handler 立即开始(来自 t=5 那次排队)
                                                                            └─ msleep(20) 睡到 t≈40
t≈40    0      —                 —                  ── 第 2 次 handler ──    msleep 结束
                                    读 GPIO=0; last_gpio_state=0 → 相等
                                    debounce_skipped+1(=1)                            ← 这次没上报
t≈40+ε  —      —                 —                  → IDLE
----------------------------------------------------------------------------------------------------
结果: irq_count=3, event_count=1, debounce_skipped=1   （注意 3 ≠ 1+1；延时从头到尾没被"重置"过）
```

读这张图的关键三点：

1. **延时从未被重置**。第 1 次 handler 从 t≈0 开始，固定睡满 20ms 到 t≈20 就读 GPIO，t=5、t=10 的中断对这次睡眠没有任何影响——既不延长也不缩短。
2. **t=5 的中断让 work 多跑了一次**。因为此时 work 正在睡眠（pending 位为空），`schedule_work()` 成功，于是 work 在第 1 次跑完后会**再跑一次**（第 2 次于 t≈40 执行）。t=10 的中断则因为 work 已 pending，变成 no-op。
3. **真正挡住重复事件的是状态比较**。第 2 次 handler 读到 `current_state=0` 与 `last_gpio_state=0` 相等，走 `else` 分支不上报，所以应用层只收到一次"按下"。`debounce_skipped` 记的就是这种"白跑一趟"的次数。

## 当前实现的真实语义（普通 `schedule_work` + `msleep`）

先澄清一个常见的误解：本驱动用的 `schedule_work()` **并不会**因为重复中断而"重置延时"。同一个 `work_struct` 在内核里只能 pending 一次，`schedule_work()` 的行为分两种情况：

- work 还在队列里 **pending（没开始跑）**：再次调用直接返回 0，**完全 no-op**，既不挪到队尾也不重置任何东西；
- work **正在运行（handler 已进入 `msleep`）**：pending 位是清的，这次调用会成功，**但效果是"当前这次跑完之后再排队跑一次"，绝不会打断或重置当前正在睡的 `msleep`**。

所以当前实现的真实延时语义是 **"第一次中断 + 20ms"**（外加每 20ms 一次的重复采样），**不是**"最后一次中断 + 20ms"。它在实践中"看起来能消抖"，主要功劳其实落在 `last_gpio_state` 状态比较上——多次 handler 执行里只有状态真正变化那次才上报。把这点理解清楚，才不会误以为延时被反复重置。

## 想要"最后一次中断 + 20ms"？改用 `delayed_work`

如果你希望"抖动期每次中断都把采样点往后推、只在最后一次抖动后再等 20ms 才读一次"，普通 `schedule_work()` 做不到，应该用 `delayed_work` + `mod_delayed_work()`：

```c
/* 结构体：work_struct 改成 delayed_work */
struct delayed_work dwork;

/* 初始化：INIT_WORK 换成 INIT_DELAYED_WORK */
INIT_DELAYED_WORK(&dev->dwork, key_work_handler);

/* 中断里：每次都"重新计时"为 20ms 后执行 */
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    struct key_debounce_dev *dev = dev_id;
    atomic_inc(&dev->irq_count);
    mod_delayed_work(system_wq, &dev->dwork, msecs_to_jiffies(DEBOUNCE_MS));
    return IRQ_HANDLED;
}

/* handler 里：去掉 msleep，直接读已经稳定的 GPIO */
static void key_work_handler(struct work_struct *work) {
    struct key_debounce_dev *dev =
        container_of(to_delayed_work(work), struct key_debounce_dev, dwork);
    int current_state = key_get_state(dev->gpio);   /* 不再 msleep */
    /* ……后面的状态比较、上报逻辑不变…… */
}

/* remove 里：cancel_work_sync 换成 cancel_delayed_work_sync */
cancel_delayed_work_sync(&dev->dwork);
```

`mod_delayed_work()` 会取消尚未触发的定时器并重新计时，所以抖动期每次中断都把执行点往后推，**只在最后一次中断后 20ms 才真正执行一次**。这样一轮抖动通常只跑一次 handler，消抖更干净，`debounce_skipped` 也会明显变小。

::: warning 别把两种语义混着讲

| 维度 | `schedule_work` + `msleep`（**当前源码**） | `mod_delayed_work`（改进方案） |
|---|---|---|
| 真实延时语义 | 第一次中断 + 20ms | 最后一次中断 + 20ms |
| 抖动期多次中断 | 部分 no-op，部分让 work"跑完再跑一次" | 每次都重新计时，最终只执行一次 |
| 延时会被"重置"吗 | **不会** | 会 |
| 一轮抖动的 handler 次数 | 通常 ≥ 2 次 | 通常 1 次 |
| 消抖主要靠 | 状态比较（延时不可靠） | 延时本身 + 状态比较（双保险） |

本驱动源码用的是左边那一列。本文按源码现状描述，右边只作为"想做到更好"的改进建议。
:::

## 本章小结

消抖算法的核心是延时读取 + 状态比较。中断触发时不立即读取，而是调度工作队列，等 20ms 后再读取 GPIO 状态。只有当前状态和上一次状态不同时，才报告事件。

这个算法简单，但在当前实现（普通 `schedule_work` + `msleep`）下要正确理解它的行为：抖动期间的后续中断**并不会重置那个 20ms 延时**，handler 仍从第一次中断起固定睡满 20ms；真正把多余采样过滤掉的是 `last_gpio_state` 状态比较——多次 handler 执行里，只有状态真正变化那次才上报，其余的走 `else` 分支记进 `debounce_skipped`。

换句话说，状态比较才是这套算法可靠性的主心骨；延时只是"让 GPIO 大致稳定"的粗筛。如果你想让延时本身也能扛住"最后一次中断后 20ms"的语义，需要升级成 `delayed_work`，见上一节。

下一章我们会讲同步机制，看看为什么需要自旋锁和等待队列，它们是如何保证多线程安全的。

---

**相关文档**：
- [工作队列机制](03_work_queue.md)
- [同步机制详解](05_synchronization.md)
