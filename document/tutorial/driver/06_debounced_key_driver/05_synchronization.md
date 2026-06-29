# 同步机制 - 并发是内核的常态

前面我们讲了中断、工作队列、消抖算法，现在要讲一个容易被忽视但极其重要的主题：同步机制。内核里有很多并发的场景——多个 CPU 可能同时执行代码，中断可能随时打断进程，工作队列和进程可能同时访问数据。如果没有合适的同步机制，你的代码会在某个随机的时刻崩溃，而且很难复现和调试。

## 为什么需要同步

让我们看看我们的驱动里有哪些并发场景：

```c
// 场景一：工作队列处理函数在进程上下文里改写共享状态
static void key_work_handler(struct work_struct *work) {
    // ... 读取 GPIO ...
    dev->last_gpio_state = current_state;   // kworker 线程，进程上下文
    dev->event_ready = true;
    // ...
}

// 中断处理函数（顶半部）只做两件本身安全的事，并不碰上面的共享字段：
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    atomic_inc(&dev->irq_count);            // 原子操作，天然安全
    schedule_work(&dev->work);              // 只是排队，不访问共享状态
    return IRQ_HANDLED;
}

// 场景二：多个进程同时调用 read()
static ssize_t key_read(struct file* filp, char __user* buf, ...) {
    wait_event_interruptible(dev->waitq, dev->event_ready);  // 进程 A
    // ...
    dev->event_ready = false;  // 进程 B
}
```

如果没有同步保护，这些场景可能导致数据竞争、状态不一致、甚至内核 panic。

::: warning 踩坑经历
我第一次写这个驱动的时候，就没加同步保护。大部分时间运行正常，但偶尔会读到奇怪的值，或者事件丢失。查了好久才发现是并发问题。这种 bug 最难调试，因为它不是每次都出现，而且很难复现。
:::

## 自旋锁（Spinlock）

自旋锁是最基本的同步机制。它的原理很简单：一个线程尝试获取锁，如果锁已经被占用，就"自旋"（在一个循环里等待），直到锁被释放。

```c
spinlock_t lock;
unsigned long flags;

// 获取锁（同时关闭中断）
spin_lock_irqsave(&dev->lock, flags);

// 临界区：访问共享数据
dev->last_gpio_state = current_state;
dev->key_value = !current_state;

// 释放锁（恢复中断）
spin_unlock_irqrestore(&dev->lock, flags);
```

### 为什么用 _irqsave 版本

你可能见过好几种自旋锁函数：`spin_lock()`、`spin_lock_irq()`、`spin_lock_irqsave()`。我们用 `_irqsave` 版本，这是最安全的选择。

```c
spin_lock(&lock);          // 不关闭中断
spin_lock_irq(&lock);      // 关闭本地中断
spin_lock_irqsave(&lock, flags);  // 关闭本地中断，保存之前的状态
```

`_irqsave` 版本不仅获取锁，还关闭本地中断，并保存之前的中断状态。为什么需要关闭中断？因为中断处理函数可能也会访问这个锁。如果中断在持有锁的时候发生，中断处理函数尝试获取同一个锁，就会死锁——中断处理函数自旋等待锁释放，但锁的持有者（被打断的代码）要等中断结束才能继续，互相等待。

::: tip 死锁场景
```
进程上下文持有锁 → 中断触发 → 中断处理函数尝试获取同一个锁 → 死锁
```

使用 `spin_lock_irqsave()` 可以避免这个场景，因为获取锁时中断已被关闭，中断不会在持有锁的时候发生。
:::

### 临界区要尽可能短

自旋锁的临界区必须尽可能短，不能有睡眠操作。

```c
spin_lock_irqsave(&dev->lock, flags);
// ✅ 快速操作
dev->last_gpio_state = current_state;
dev->event_ready = true;

// ❌ 不能睡眠
// msleep(20);  // 绝对不行！
spin_unlock_irqrestore(&dev->lock, flags);
```

如果临界区里有睡眠操作，其他等待锁的 CPU 会空转浪费 CPU 时间，而且可能导致系统响应变慢。

### 我们在哪里使用自旋锁

在我们的驱动里，工作处理函数里访问共享数据时使用了自旋锁：

```c
static void key_work_handler(struct work_struct* work) {
    // ... 读取 GPIO ...

    spin_lock_irqsave(&dev->lock, flags);

    if (current_state != dev->last_gpio_state) {
        dev->last_gpio_state = current_state;
        dev->key_value = !current_state;
        dev->event_ready = true;
        wake_up_interruptible(&dev->waitq);
        atomic_inc(&dev->event_count);
    } else {
        atomic_inc(&dev->debounce_skipped);
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}
```

这里需要保护 `last_gpio_state`、`key_value`、`event_ready` 这些字段，因为它们可能被其他地方（比如 read 函数）同时访问。

## 等待队列（Wait Queue）

等待队列用于让进程睡眠等待某个事件，当事件发生时再唤醒它。这是实现阻塞 I/O 的标准方式。

```c
wait_queue_head_t waitq;

// 初始化
init_waitqueue_head(&dev->waitq);

// 在 read() 里等待
wait_event_interruptible(dev->waitq, dev->event_ready);

// 在工作函数里唤醒
wake_up_interruptible(&dev->waitq);
```

### wait_event_interruptible 宏

`wait_event_interruptible()` 是一个宏，它的作用是：如果条件为假，让进程睡眠；如果条件为真，立即返回。

```c
wait_event_interruptible(dev->waitq, dev->event_ready);
```

展开后大致是这样：

```c
while (!dev->event_ready) {
    // 把当前进程加入等待队列
    // 让进程进入睡眠状态
    // 调度器选择其他进程运行
}
```

当某个地方调用 `wake_up_interruptible(&dev->waitq)` 时，睡眠的进程会被唤醒，重新检查条件。如果条件为真，返回；如果条件仍为假，继续睡眠。

### 我们的 read 函数

```c
static ssize_t key_read(struct file* filp, char __user* buf,
                        size_t cnt, loff_t* offt)
{
    struct key_debounce_dev* dev = filp->private_data;
    int key_value;
    unsigned long flags;

    /* 等待事件就绪 */
    if (wait_event_interruptible(dev->waitq, dev->event_ready)) {
        return -ERESTARTSYS;
    }

    /* 读取数据 */
    spin_lock_irqsave(&dev->lock, flags);
    key_value = dev->key_value;
    dev->event_ready = false;
    spin_unlock_irqrestore(&dev->lock, flags);

    /* 拷贝到用户空间 */
    if (copy_to_user(buf, &key_value, sizeof(key_value))) {
        return -EFAULT;
    }

    return sizeof(key_value);
}
```

这个函数的核心是 `wait_event_interruptible()`。如果没有新事件，进程会睡眠在这里。当工作队列调用 `wake_up_interruptible()` 时，进程被唤醒，读取数据并返回给用户空间。

::: tip 为什么用 _interruptible 版本
`_interruptible` 版本可以被信号中断，这对于用户交互的设备是个好特性。用户按 Ctrl+C 时，read() 会返回 `-ERESTARTSYS`，而不是傻等。
:::

## 原子变量（Atomic）

原子变量是硬件保证原子性的整数类型，不需要锁就能安全地读写和递增。

```c
atomic_t irq_count;

// 递增
atomic_inc(&dev->irq_count);

// 读取
int count = atomic_read(&dev->irq_count);
```

原子变量内部使用特殊的 CPU 指令（比如 ARM 的 `LDXR`/`STXR`），确保操作的原子性。即使是多 CPU 同时递增，结果也是正确的。

### 我们在哪里使用原子变量

我们的驱动用原子变量来统计信息：

```c
// 中断处理函数里
atomic_inc(&dev->irq_count);

// 工作函数里
atomic_inc(&dev->event_count);
atomic_inc(&dev->debounce_skipped);
```

这些统计信息不需要严格的同步，但也不能出现错误的值（比如两个中断同时递增，结果只加了 1）。原子变量正好满足这个需求。

::: tip 原子变量 vs 自旋锁
原子变量适用于简单的计数和标志位。如果操作比较复杂（比如多个字段需要一起更新），还是用自旋锁更合适。我们的驱动两者都用：原子变量用于统计，自旋锁用于状态保护。
:::

## 各种同步机制的选择

内核提供了多种同步机制，选择合适的很重要：

| 机制 | 适用场景 | 能否睡眠 |
|------|----------|----------|
| 自旋锁 | 短期临界区，多 CPU | 否 |
| 互斥锁（Mutex） | 长期临界区，单线程上下文 | 是 |
| 读写锁（RW Lock） | 读多写少的临界区 | 否 |
| 完成量（Completion） | 等待一次性事件 | 是 |
| 等待队列（Wait Queue） | 等待事件，阻塞 I/O | 是 |
| 原子变量 | 简单计数和标志位 | N/A |

对于我们的按键驱动，选择是明确的：自旋锁保护状态，等待队列实现阻塞 I/O，原子变量统计信息。

::: info 为什么不用互斥锁
互斥锁可以睡眠，所以不能在中断上下文使用。我们的中断处理函数需要递增 `irq_count`，只能用原子变量。工作队列可以用互斥锁，但自旋锁已经足够了。
:::

## 调试并发问题

并发问题是最难调试的，因为它们是非确定性的——不一定每次都出现。这里有一些技巧：

1. **开启内核并发检测**：
```bash
echo 1 > /proc/sys/kernel/lockdep
```
Lockdep 可以检测死锁风险，虽然它有运行时开销，但对于调试很有用。

2. **使用 KCSAN 检测数据竞争**：
内核配置里开启 `CONFIG_KCSAN`，可以检测未同步的并发访问。

3. **代码审查**：
仔细检查所有共享数据的访问，确保都有合适的同步保护。

::: warning 难以复现的 bug
并发问题往往在压力测试或多 CPU 系统上才出现。单 CPU 或轻负载时可能一切正常，但多 CPU 高负载时就崩溃了。所以测试时要覆盖各种场景。
:::

## 本章小结

同步机制是内核编程的基础。我们的驱动使用了三种同步机制：自旋锁保护状态数据，等待队列实现阻塞 I/O，原子变量统计信息。这些机制保证了代码在多 CPU、中断上下文混合访问的情况下仍然正确。

说实话，理解这些同步机制需要时间和经验。一开始可能会困惑为什么要用这么多不同的锁，为什么这个地方用自旋锁而那个地方用原子变量。但随着代码量的增加，你会慢慢理解它们的设计意图和使用场景。

下一章我们会讲输出分析，看看如何通过日志和统计验证驱动是否正常工作，消抖是否有效。

---

**相关文档**：
- [消抖算法实现](04_debounce_algorithm.md)
- [输出分析](06_output_analysis.md)
