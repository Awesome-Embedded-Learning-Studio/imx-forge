# 轮询实现 - 在循环里等按键

前面我们讲了怎么配置 GPIO 为输入，怎么读取状态。现在我们把这些操作组合起来，实现一个完整的轮询式按键驱动。

说实话，轮询这个概念一开始让我有点困惑。你说 `read()` 函数应该读一次就返回吧？但按键什么时候按下谁知道啊，那 `read()` 怎么知道什么时候有数据可读？

后来才明白，轮询式的 `read()` 函数可以一直阻塞，直到按键状态发生变化才返回。这就是所谓的"阻塞 I/O"。

## 轮询的基本思想

轮询的核心思路特别简单：

```c
while (1) {
    当前状态 = 读取GPIO();
    if (当前状态 != 上次状态) {
        /* 状态变化了，返回给应用 */
        返回给用户;
    }
    /* 状态没变，继续等 */
}
```

这个循环会一直跑，直到检测到状态变化。用户程序调用 `read()` 的时候，会在这里一直等着，有按键动作了才会返回。

## 完整的 read 函数实现

我们的轮询式 `read()` 函数是这样的：

```c
static ssize_t key_read(struct file *file, char __user *buf, size_t count, loff_t *ppos)
{
    struct key_gpio_dev *dev = file->private_data;
    int last_state, current_state;

    /* 先获取当前状态 */
    last_state = key_get_state(dev->gpio);

    /* 循环等待状态变化 */
    while (1) {
        /* 检查是否有信号（如用户按 Ctrl+C） */
        if (signal_pending(current)) {
            return -ERESTARTSYS;
        }

        /* 读取当前状态 */
        current_state = key_get_state(dev->gpio);

        /* 状态变化了 */
        if (current_state != last_state) {
            /* 转换为应用层格式：1=按下，0=松开 */
            int key_value = !current_state;
            if (copy_to_user(buf, &key_value, sizeof(key_value))) {
                return -EFAULT;
            }
            return sizeof(key_value);
        }

        /* 让出 CPU，避免完全占用 */
        schedule();
    }
}
```

这个函数值得逐行分析，里面有几个关键点。

## signal_pending()：处理用户信号

```c
if (signal_pending(current)) {
    return -ERESTARTSYS;
}
```

这是处理用户信号的地方。如果用户在终端按了 `Ctrl+C`，内核会发送 `SIGINT` 信号给进程。`signal_pending()` 检查是否有这样的信号挂起。

为什么要处理这个？你想想，如果用户按了 `Ctrl+C`，但我们的 `read()` 函数还在死循环里等着，进程就无法正常退出。所以检测到信号时，我们返回 `-ERESTARTSYS`，告诉系统"这个系统调用被中断了，需要重启"。

::: info -ERESTARTSYS 的特殊含义

`-ERESTARTSYS` 是一个特殊的错误码，它不是普通的应用层错误。当系统调用返回这个值时，内核会自动重启系统调用（如果设置了 `SA_RESTART` 标志）。

但对于 `Ctrl+C` 这种情况，用户本来就想退出程序，系统不会重启，而是让 `read()` 返回 `-EINTR`，应用层就能收到错误并退出。
:::

## copy_to_user()：数据必须这样复制

```c
int key_value = !current_state;
if (copy_to_user(buf, &key_value, sizeof(key_value))) {
    return -EFAULT;
}
```

这个很重要：**从内核空间到用户空间的数据传输必须用专用函数**。

你不能直接 `memcpy`，也不能直接赋值。因为内核空间和用户空间的地址映射是分开的，而且可能有保护机制。`copy_to_user()` 内部会处理这些细节：

```c
/* copy_to_user 的内部逻辑（简化） */
bool copy_to_user(void __user *to, const void *from, unsigned long n)
{
    /* 检查用户空间地址是否有效 */
    if (!access_ok(to, n))
        return true;

    /* 执行复制，处理可能的页面错误 */
    return __copy_to_user(to, from, n) != 0;
}
```

返回值是 `true` 表示失败，`false` 表示成功。这个方向有点反直觉，所以代码里用 `if (copy_to_user(...))` 来判断错误。

::: warning 常见的内核崩溃原因

忘记用 `copy_to_user` 直接写用户空间指针，会直接触发内核 panic。这是新手常犯的错误，包括我当初也是这么过来的。

更危险的是，这种问题可能不会立即暴露。用户空间地址有时候恰好可写，代码能跑；但换个地址或换个环境就炸了。这种随机性的 bug 特别难调试。
:::

## schedule()：别把 CPU 吃光了

```c
schedule();
```

这一行很短，但作用重大。

如果没有 `schedule()`，这个 `while(1)` 循环会 100% 占用一个 CPU 核心。你用 `top` 命令一看，某个 CPU 核心占用率一直是 100%，系统负载飙升。

`schedule()` 的作用是：**当前进程主动让出 CPU，让其他进程有机会运行**。

::: tip 调度器的工作原理

Linux 调度器维护着一个可运行进程队列。正常情况下，进程用完时间片或主动阻塞时，调度器会选择下一个进程运行。

但在 `while(1)` 这种死循环里，进程永远不会主动阻塞，所以调度器永远不会切换。`schedule()` 告诉调度器："我不抢了，换个进程吧"。

这样，其他进程才有机会运行，系统才不会卡死。
:::

## 轮询方式的性能问题

说实话，轮询方式的性能确实不太好。即使加了 `schedule()`，CPU 占用率还是偏高：

```
# 用 top 观察测试程序的 CPU 占用
%CPU
───────
45.2   <-- 轮询式的按键测试程序
```

这是因为 `schedule()` 只是"让出一下"，进程很快又被调度器选中继续运行。整个循环还是在不停地跑，只是别占那么狠而已。

::: warning 轮询方式的真实开销

轮询方式的 CPU 占用取决于循环频率。在我们的实现里，循环频率大约是：

每次循环：
- GPIO 读操作：~1us
- schedule 开销：~10us
- 其他判断：~1us

总共 ~12us，所以每秒能跑约 80000 次循环。这意味着每秒要读 80000 次 GPIO，即使按键没被按下。

这就是为什么轮询方式效率低——大量的无效读取。
:::

## 用户空间的测试程序

为了测试这个驱动，我们写个小程序：

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

int main(void) {
    int fd = open("/dev/imxaes_key", O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Waiting for key press... (Ctrl+C to exit)\n");

    int value;
    while (read(fd, &value, sizeof(value)) == sizeof(value)) {
        if (value == 1) {
            printf("Key PRESSED\n");
        } else {
            printf("Key RELEASED\n");
        }
    }

    close(fd);
    return 0;
}
```

这个程序很简单：打开设备，循环 `read()`，打印结果。运行它，然后按板子上的按键，你会看到输出。

::: tip 快速测试方法

如果你不想写程序，直接用命令行也能测试：

```bash
# 方法 1：用 cat
cat /dev/imxaes_key

# 方法 2：用 hexdump 看原始数据
hexdump -C /dev/imxaes_key
```

按按键的时候会输出数据，按 `Ctrl+C` 退出。这种方式适合快速验证驱动是否工作。
:::

## 小结一下

轮询方式的实现要点：

1. **在 `read()` 里循环等待**——直到状态变化才返回
2. **检查信号**——`signal_pending()` 处理 `Ctrl+C`
3. **用 `copy_to_user`**——不能直接写用户空间
4. **调用 `schedule()`**——避免 100% 占用 CPU

优点是代码简单直观，缺点是 CPU 占用高。作为一个教学示例，它让初学者能理解输入设备的基本工作原理。

但轮询方式不适合实际应用。你想想，一个完整的系统有很多输入设备，如果每个都轮询，CPU 早就撑不住了。下一章我们会讨论按键抖动的问题，然后学习更高效的中断方式。

---

**上一章**: [GPIO 输入机制](./02_gpio_input_mechanism.md) | **下一章**: [抖动现象](./04_bounce_phenomenon.md)
