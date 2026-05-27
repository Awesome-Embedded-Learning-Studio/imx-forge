# 输出分析 - 验证消抖效果

前面我们讲了中断、工作队列、消抖算法、同步机制，现在我们来谈谈怎么验证驱动是否正常工作。说实话，写代码只是第一步，验证代码正确性才是真正的挑战。尤其是消抖这种涉及时序的功能，不好调试。

## 内核日志分析

驱动加载后，我们可以通过内核日志查看初始化过程：

```bash
dmesg | tail -20
```

正常情况下，你会看到类似的输出：

```
[12345.678] key_probe: probing device
[12345.679] key_hw_init: GPIO initialized successfully
[12345.680] key_hw_request_irq: IRQ 256 requested (imxaes_key_debounce)
[12345.681] key_probe: device registered as imxaes_key_debounce (major 240, IRQ 256)
```

如果看到这些日志，说明驱动初始化成功了。如果没有看到，或者有错误信息，需要检查硬件配置和设备树。

::: tip 调试技巧
如果驱动加载失败，可以用 `dmesg | grep -i error` 查找错误信息。大部分错误都会打印详细的错误码和描述。
:::

## 卸载时的统计

驱动卸载时会打印统计信息，这是验证消抖效果的关键数据：

```bash
rmmod 18_tutorial_key_debounce_driver
dmesg | tail -5
```

你会看到类似这样的输出：

```
[23456.789] key_remove: removing device
[23456.790] key_remove: statistics - IRQs: 150, events: 5, skipped: 145
```

这个统计告诉我们：
- **IRQs: 150**：中断触发了 150 次
- **events: 5**：实际报告了 5 个事件（可能是 3 次按下，2 次松开）
- **skipped: 145**：145 次抖动被过滤

::: info 为什么中断次数远大于事件次数
这是正常的！按键按下/松开各触发 1 次中断，抖动期间可能触发多次中断。工作队列 20ms 后才读取，只有最终状态才报告事件。所以中断次数 >> 事件次数是消抖在工作的证明。
:::

## 统计信息的含义

驱动维护了三个计数器，在 `struct key_debounce_dev` 里：

```c
atomic_t irq_count;        // 中断次数
atomic_t event_count;      // 实际事件次数
atomic_t debounce_skipped; // 被过滤的抖动次数
```

### irq_count

每次中断触发时递增：

```c
static irqreturn_t key_irq_handler(int irq, void *dev_id) {
    atomic_inc(&dev->irq_count);
    schedule_work(&dev->work);
    return IRQ_HANDLED;
}
```

这个计数器反映了中断触发的频率。正常情况下，按一次按键（按下+松开）会触发 2 次中断，但由于抖动，实际中断次数可能远大于 2。

### event_count

只有状态真正变化时才递增：

```c
if (current_state != dev->last_gpio_state) {
    dev->last_gpio_state = current_state;
    dev->key_value = !current_state;
    dev->event_ready = true;
    wake_up_interruptible(&dev->waitq);
    atomic_inc(&dev->event_count);
}
```

这个计数器反映了报告给用户空间的事件数。按一次按键（按下+松开）会产生 2 个事件（1 个按下，1 个松开）。

### debounce_skipped

状态没有变化时递增：

```c
} else {
    atomic_inc(&dev->debounce_skipped);
}
```

这个计数器反映了被过滤的抖动次数。如果这个数值很高，说明消抖在有效工作。

## 正常的统计模式

正常情况下，统计信息应该有这样的模式：

```
按一次按键：
- IRQs: 50-200 次（取决于按键抖动情况）
- events: 2 次（1 次按下，1 次松开）
- skipped: 48-198 次

连续按 3 次按键：
- IRQs: 150-600 次
- events: 6 次（3 次按下，3 次松开）
- skipped: 144-594 次
```

如果你看到 `IRQs ≈ events × 2`，说明按键几乎没有抖动（或者你的按键质量特别好）。如果你看到 `IRQs >> events × 2`，说明消抖在有效工作。

::: tip 对比测试
你可以禁用消抖（把延时改为 0），对比统计信息。禁用消抖后，`events` 应该会接近 `IRQs`，说明每次中断都产生了事件（包括抖动）。
:::

## poll 支持

我们的驱动实现了 `poll` 函数，支持非阻塞 I/O：

```c
static __poll_t key_poll(struct file* file, struct poll_table_struct* pt)
{
    struct key_debounce_dev* dev = file->private_data;
    __poll_t mask = 0;

    poll_wait(file, &dev->waitq, pt);

    if (dev->event_ready) {
        mask = EPOLLIN | EPOLLRDNORM;
    }

    return mask;
}
```

这个函数让用户空间可以用 `select()`、`poll()`、`epoll()` 监听按键事件，而不必阻塞在 `read()` 上。

::: info poll 的使用场景
poll 最常见的场景是同时监听多个文件描述符。比如一个 GUI 程序可能同时监听鼠标、键盘、网络事件，用 poll 可以在一个线程里处理所有事件。
:::

## 用户空间的测试程序

一个简单的测试程序可以验证驱动是否正常工作：

```c
int main(void) {
    int fd = open("/dev/imxaes_key_debounce", O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Press the key (Ctrl+C to exit)...\n");

    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN,
    };

    while (1) {
        int ret = poll(&pfd, 1, -1);
        if (ret < 0) {
            perror("poll");
            break;
        }

        int value;
        if (read(fd, &value, sizeof(value)) == sizeof(value)) {
            printf("Key: %s\n", value ? "PRESSED" : "RELEASED");
        }
    }

    close(fd);
    return 0;
}
```

编译运行：

```bash
gcc test_key.c -o test_key
./test_key
```

按几次按键，你应该看到类似这样的输出：

```
Press the key (Ctrl+C to exit)...
Key: PRESSED
Key: RELEASED
Key: PRESSED
Key: RELEASED
```

如果看到很多连续的 PRESSED 或 RELEASED，说明消抖没有正常工作。

## 常见问题分析

### 没有任何输出

如果按按键没有任何输出，检查：
1. 驱动是否加载成功：`lsmod | grep key`
2. 设备节点是否存在：`ls -l /dev/imxaes_key_debounce`
3. 内核日志是否有错误：`dmesg | grep -i error`

### 大量重复事件

如果看到很多连续的 PRESSED 或 RELEASED：
1. 检查消抖延时是否足够（20ms 可能不够）
2. 检查按键硬件是否有严重抖动
3. 查看统计信息，`debounce_skipped` 应该很高

### 事件丢失

如果按按键但偶尔没有输出：
1. 检查中断是否真的触发：`cat /proc/interrupts | grep imxaes`
2. 检查 GPIO 配置是否正确
3. 检查工作队列是否正常

## 性能分析

中断方式的按键驱动在 CPU 占用上几乎可以忽略不计。我们可以用 `top` 验证：

```bash
# 运行测试程序
./test_key

# 另一个终端查看 CPU 占用
top
```

即使频繁按按键，CPU 占用也应该接近 0。这是因为 CPU 只在中断触发和工作队列执行时才干活，大部分时间在空闲或睡眠。

对比轮询方式的驱动，CPU 占用会明显高一些。轮询方式需要持续读取 GPIO，CPU 无法真正空闲。

::: tip 功耗对比
中断方式不仅 CPU 占用低，功耗也更低。CPU 可以进入深度睡眠，只在中断触发时醒来。轮询方式需要定期唤醒，无法进入深度睡眠，功耗更高。
:::

## 本章小结

输出分析是验证驱动正确性的关键步骤。通过内核日志、统计信息、用户空间测试，我们可以全面了解驱动的工作状态。正常情况下，中断次数应该远大于事件次数，`debounce_skipped` 应该比较高，这证明消抖在有效工作。

poll 支持让驱动可以用于更复杂的应用场景，非阻塞 I/O 对于多路复用很重要。性能分析证明了中断方式相比轮询方式的优势：CPU 占用低，功耗低，响应及时。

下一章我们会讲如何编译和测试驱动，从源码到运行的全过程。

---

**相关文档**：
- [同步机制详解](05_synchronization.md)
- [编译和测试](07_build_and_test.md)
