# 工作队列 - 中断里的那些事为什么不能做

上一章我们讲了中断处理函数必须快速返回，不能睡眠。但按键消抖需要延时 20ms，这显然不能在中断处理函数里做。那怎么办？答案就是工作队列。

说实话，工作队列这个概念一开始让我很困惑。为什么需要这么复杂的东西？后来慢慢理解了，这其实是内核为了解决一个根本问题而设计的：**中断上下文和进程上下文的分离**。

## 中断上下文的限制

中断处理函数运行在中断上下文，不是进程上下文。这意味着什么？

```c
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    // ❌ 这些都不能做！
    msleep(20);           // 不能睡眠
    mutex_lock(&lock);    // 互斥锁可能睡眠
    kmalloc(GFP_KERNEL);  // GFP_KERNEL 可能睡眠

    // ✅ 这些可以做
    spin_lock(&lock);     // 自旋锁不睡眠
    atomic_inc(&counter); // 原子操作
    schedule_work(&work);  // 调度工作队列

    return IRQ_HANDLED;
}
```

为什么不能睡眠？因为中断处理函数没有"进程"的概念，没有进程控制块，没有调度器能恢复它。如果它睡眠了，调度器不知道怎么唤醒它，系统就死锁了。

::: warning 踩坑经历
我第一次写中断处理函数的时候，不知道这些限制，直接在里面调用了 `msleep()`。结果系统直接 panic 了，内核日志显示"sleeping function called from invalid context"。查了半天才知道，中断上下文不能睡眠。这个错误我到现在还记得，因为当时花了一整天才搞明白。
:::

## 工作队列的核心思想

工作队列的思路很巧妙：**把工作推迟到进程上下文执行**。

具体来说，中断处理函数（中断上下文）只做一件事：调度一个工作。这个工作会被添加到一个队列里，由内核线程（进程上下文）来执行。因为是进程上下文，所以可以睡眠，可以调用任何 API。

```c
// 中断处理函数（中断上下文）
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    schedule_work(&dev->work);  // 只是调度工作，立即返回
    return IRQ_HANDLED;
}

// 工作队列处理函数（进程上下文）
static void key_work_handler(struct work_struct *work) {
    msleep(20);  // 可以睡眠！
    // 做实际的处理...
}
```

这就像你正在忙一件事情（中断上下文），突然有人来找你。你不能停下来处理他，但你可以在你的待办清单上加一项（调度工作）。等你有空的时候（进程上下文），再去处理待办清单上的事情。

## 工作队列的 API

Linux 的工作队列 API 很简洁。首先定义一个工作：

```c
struct work_struct work;
```

然后初始化它，关联处理函数：

```c
INIT_WORK(&dev->work, key_work_handler);
```

之后就可以调度了：

```c
schedule_work(&dev->work);
```

`schedule_work()` 会把工作添加到系统工作队列（`system_wq`），这个队列由一组内核线程管理。当工作被调度后，某个内核线程会在适当的时候执行我们的处理函数。

::: tip 系统工作队列
Linux 提供了一个默认的系统工作队列 `system_wq`，大多数情况下够用了。如果你的工作有特殊需求（比如高优先级、必须尽快执行），可以创建专用的工作队列。但对于按键这种低速设备，system_wq 完全足够。
:::

## 工作处理函数

工作处理函数的签名是固定的：

```c
static void key_work_handler(struct work_struct *work)
{
    struct key_debounce_dev* dev =
        container_of(work, struct key_debounce_dev, work);

    /* 可以睡眠！ */
    msleep_interruptible(DEBOUNCE_MS);

    /* 读取 GPIO 状态 */
    int current_state = key_get_state(dev->gpio);

    /* ... 处理逻辑 ... */
}
```

`container_of()` 宏用于从 `work_struct` 指针反推出包含它的结构体指针。这个宏在内核里用得很广泛，如果你不理解它，建议花点时间研究一下。

处理函数是进程上下文，所以可以睡眠，可以调用任何 API。`msleep_interruptible()` 可以被信号中断，这对于用户交互的设备是个好选择——用户按 Ctrl+C 可以中断睡眠。

## schedule_work() 的实现

`schedule_work()` 的实现其实很简单（在 `kernel/workqueue.c` 里）：

```c
bool schedule_work(struct work_struct *work)
{
    return queue_work(system_wq, work);
}
```

它就是把工作添加到 `system_wq` 这个工作队列里。`queue_work()` 会做这些事情：

1. 把工作添加到队列的链表
2. 唤醒工作队列的内核线程
3. 内核线程会从队列里取出工作并执行

::: info 工作队列的内核线程
工作队列由内核线程（kworker）执行。你可以在系统里看到这些线程：
```bash
ps aux | grep kworker
```
每个 CPU 都有若干个 kworker 线程，它们负责执行工作队列里的任务。
:::

## 工作队列 vs 定时器

你可能会问，为什么不用定时器？定时器也能实现延时啊。

定时器确实能实现延时，但它运行在中断上下文（实际上叫软中断上下文），仍然不能睡眠。如果你只是需要在某个时刻执行一些不睡眠的操作，定时器是个好选择。但如果你需要睡眠，工作队列是唯一的选择。

```c
// 定时器（中断上下文，不能睡眠）
static void key_timer_handler(struct timer_list *timer) {
    // ❌ msleep(20);  // 不能睡眠！
}

// 工作队列（进程上下文，可以睡眠）
static void key_work_handler(struct work_struct *work) {
    // ✅ msleep(20);  // 可以睡眠！
}
```

::: tip 选择指南
- 需要睡眠：用工作队列
- 不需要睡眠且需要精确时序：用定时器
- 延时很短（微秒级）：用高精度定时器（hrtimer）

对于按键消抖这种需要 20ms 延时且需要读取 GPIO（可能睡眠）的场景，工作队列是最佳选择。
:::

## msleep vs msleep_interruptible

我们的工作函数用 `msleep_interruptible()` 而不是 `msleep()`，有什么区别？

```c
msleep(20);               // 不可中断的睡眠
msleep_interruptible(20); // 可被信号中断的睡眠
```

`msleep()` 会睡眠指定的毫秒数，期间不会被中断。如果进程收到信号（比如 Ctrl+C），睡眠不会被中断。

`msleep_interruptible()` 可以被信号中断。如果进程收到信号，它会立即返回，返回值是实际睡眠的毫秒数（可能小于指定值）。

对于用户交互的设备（比如按键），`msleep_interruptible()` 是更好的选择。用户按 Ctrl+C 退出程序时，工作队列能快速响应，而不是傻等 20ms。

## 工作队列的调试

工作队列的问题通常不难调试，因为它是进程上下文，可以打印日志，可以追踪。

你可以在工作处理函数里加打印：

```c
static void key_work_handler(struct work_struct *work) {
    pr_info("Work handler started\n");
    msleep_interruptible(DEBOUNCE_MS);
    pr_info("Work handler finished\n");
}
```

如果工作没有被调度，检查中断处理函数是否真的调用了 `schedule_work()`。如果工作被调度了但没有执行，检查工作队列是否正常（看看 kworker 线程是否存在）。

::: tip 调试工具
```bash
# 查看工作队列状态
cat /proc/workqueue

# 查看内核线程
ps aux | grep kworker
```

这些命令可以帮助你诊断工作队列相关的问题。
:::

## 本章小结

工作队列是内核里解决"中断上下文不能睡眠"问题的标准方案。中断处理函数只调度工作，实际的工作处理在进程上下文执行。这样既保证了中断响应的及时性，又允许在处理函数里做耗时操作。

对于按键消抖这种场景，工作队列几乎是完美的选择。中断触发时调度工作，20ms 后在工作处理函数里读取稳定的 GPIO 状态。整个过程对 CPU 来说开销很小，对用户来说响应及时。

下一章我们会详细讲解消抖算法的实现，看看延时读取到底怎么写，如何过滤掉那些讨厌的抖动。

---

**相关文档**：
- [中断子系统详解](02_interrupt_subsystem.md)
- [消抖算法实现](04_debounce_algorithm.md)
