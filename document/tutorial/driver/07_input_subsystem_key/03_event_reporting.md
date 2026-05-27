# 事件报告 - 告诉系统按键发生了什么

上一章我们讲了 Input 子系统的架构，知道驱动需要通过 `input_event()` 报告事件。这一章我们深入看一下事件报告的具体实现。说实话，这部分代码虽然不多，但细节还挺多的，用错了可能导致用户空间收不到事件，或者收到错误的事件。

## input_event：底层事件报告函数

`input_event()` 是事件报告的核心函数，内核定义如下：

```c
void input_event(struct input_dev *dev,
                 unsigned int type, unsigned int code, int value);
```

三个参数的含义：
- `type`：事件类型，如 `EV_KEY`（按键）、`EV_REL`（相对坐标）
- `code`：事件代码，如 `KEY_ENTER`、`BTN_LEFT`
- `value`：事件值，对于按键来说 1=按下，0=松开

::: info
按键的 value 只有 0 和 1，但其他事件类型可能有更多值。比如 `EV_REL` 的 value 是移动量（可以是正负），`EV_ABS` 的 value 是绝对坐标值。
:::

调用 `input_event()` 前要确保设备支持该事件类型，否则会被忽略：

```c
/* 确保设备支持 EV_KEY */
set_bit(EV_KEY, dev->input_dev->evbit);
set_bit(KEY_ENTER, dev->input_dev->keybit);

/* 现在可以安全报告事件 */
input_event(dev->input_dev, EV_KEY, KEY_ENTER, 1);
```

如果你报告了一个设备不支持的事件，Input Core 会默默忽略。这个设计有点坑——你不会收到任何错误提示，只是事件不生效。调试的时候如果发现事件没有传递到用户空间，第一件事就是检查设备能力是否正确设置。

## input_report_key：便利宏

对于按键事件，Input 子系统提供了便利宏 `input_report_key()`：

```c
void input_report_key(struct input_dev *dev, unsigned int code, int value)
{
    input_event(dev, EV_KEY, code, value);
}
```

这个宏其实就是 `input_event()` 的封装，省去了写 `EV_KEY` 的麻烦。实际使用：

```c
/* 报告 Enter 键按下 */
input_report_key(dev->input_dev, KEY_ENTER, 1);

/* 报告 Enter 键松开 */
input_report_key(dev->input_dev, KEY_ENTER, 0);
```

::: tip
类似的便利宏还有 `input_report_rel()`（相对坐标）、`input_report_abs()`（绝对坐标）等，对应不同的事件类型。
:::

## input_sync：事件同步点

报告事件后，必须调用 `input_sync()` 标记同步点：

```c
void input_sync(struct input_dev *dev)
{
    input_event(dev, EV_SYN, SYN_REPORT, 0);
}
```

`EV_SYN` 是同步事件类型，`SYN_REPORT` 是"一批事件结束"的标记。为什么需要这个？因为一次硬件动作可能产生多个事件，比如移动鼠标会同时报告 X 和 Y 的相对移动量。`input_sync()` 告诉子系统"这一批事件结束了"，确保用户空间原子地收到所有相关事件。

::: warning
忘记调用 `input_sync()` 是常见的错误。没有同步点，事件可能会堆积在缓冲区里，用户空间 read() 可能阻塞或者收到延迟的事件。
:::

完整的按键事件报告流程：

```c
/* 按键按下 */
input_report_key(dev->input_dev, KEY_ENTER, 1);
input_sync(dev->input_dev);

/* 按键松开 */
input_report_key(dev->input_dev, KEY_ENTER, 0);
input_sync(dev->input_dev);
```

## 按键代码：KEY_ENTER 从哪来的

我们一直在用 `KEY_ENTER`，这个常量定义在哪里？它在内核头文件 `include/uapi/linux/input-event-codes.h`：

```c
#define KEY_RESERVED      0
#define KEY_ESC           1
#define KEY_1             2
#define KEY_2             3
/* ... 数百个按键定义 ... */
#define KEY_ENTER         28
#define KEY_LEFTCTRL      29
/* ... */
```

这个文件定义了所有标准的按键代码，包括键盘键、鼠标按钮、游戏手柄按钮等。常用的有：

```c
KEY_ENTER      /* 回车键，代码 28 */
KEY_ESC        /* ESC 键，代码 1 */
KEY_1 ~ KEY_9  /* 数字键 1-9 */
KEY_LEFTSHIFT  /* 左 Shift，代码 42 */
BTN_LEFT       /* 鼠标左键，代码 272 */
BTN_RIGHT      /* 鼠标右键，代码 273 */
```

::: tip
按键代码是跨平台的标准。你在 ARM 平台上报告 `KEY_ENTER`，x86 上的用户空间程序能正确识别。这就是 Input 子系统的好处——统一的按键代码映射。
:::

## 实际驱动中的事件报告

让我们看一下实际驱动中的消抖工作函数：

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

        /* input_report_key 会自动处理 GPIO_ACTIVE_LOW */
        input_report_key(dev->input_dev, KEY_ENTER, current_state);
        input_sync(dev->input_dev);
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}
```

这里有几个重要的细节。首先是 `key_hw_get_raw_state()` 返回的是逻辑值（考虑了 GPIO_ACTIVE_LOW），所以 `current_state=1` 表示按键被按下，`current_state=0` 表示按键被松开。我们直接把这个值传给 `input_report_key()`，不需要再反转。

其次是用自旋锁保护 `last_state`。中断处理函数和工作队列可能同时访问这个变量，不加锁会有竞态条件。虽然对于单个按键这种竞态可能不会造成致命问题，但正确做法还是加锁。

::: info
为什么 `current_state` 可以直接传给 `input_report_key()`？因为 `gpiod_get_value()` 已经应用了 GPIO_ACTIVE_LOW 标志。如果设备树中指定了 `GPIO_ACTIVE_LOW`，按下按键时物理电平是 0，但 `gpiod_get_value()` 返回 1（逻辑值"按下"）。
:::

## 事件的传递路径

报告事件后，事件是如何到达用户空间的？让我们追踪一下路径：

1. **驱动调用 `input_report_key()`** → 调用 `input_event()`
2. **Input Core 处理** → `input_handle_event()` 把事件放入缓冲区
3. **唤醒 Handler** → evdev Handler 被唤醒
4. **Handler 唤醒用户空间** → 等待在 read() 的进程被唤醒

整个过程是同步的，`input_report_key()` 返回时，事件已经在内核缓冲区中了。但用户空间 read() 不一定会立即返回，这取决于 read() 的调用方式（阻塞还是非阻塞）。

## 常见错误：忘记设置 keybit

我们说过，如果设备不支持某个事件类型，报告事件会被忽略。一个常见的错误是：

```c
/* 只设置了 EV_KEY */
set_bit(EV_KEY, dev->input_dev->evbit);

/* 但忘记设置 KEY_ENTER！*/
/* set_bit(KEY_ENTER, dev->input_dev->keybit); */

/* 报告事件 */
input_report_key(dev->input_dev, KEY_ENTER, 1);
input_sync(dev->input_dev);

/* 这个事件会被默默忽略！*/
```

::: warning
`evbit` 声明支持的事件类型，`keybit` 声明支持的按键代码。两个都要设置，事件才能正确传递。
:::

正确做法：

```c
/* 设置支持按键事件 */
set_bit(EV_KEY, dev->input_dev->evbit);
set_bit(KEY_ENTER, dev->input_dev->keybit);

/* 现在可以报告事件 */
input_report_key(dev->input_dev, KEY_ENTER, 1);
input_sync(dev->input_dev);
```

## 报告多个按键

如果你的设备有多个按键，可以这样报告：

```c
/* 设置设备能力 */
set_bit(EV_KEY, dev->input_dev->evbit);
set_bit(KEY_ENTER, dev->input_dev->keybit);
set_bit(KEY_ESC, dev->input_dev->keybit);
set_bit(KEY_1, dev->input_dev->keybit);

/* 报告不同的按键 */
input_report_key(dev->input_dev, KEY_ENTER, 1);
input_sync(dev->input_dev);

input_report_key(dev->input_dev, KEY_ESC, 1);
input_sync(dev->input_dev);

input_report_key(dev->input_dev, KEY_1, 1);
input_sync(dev->input_dev);
```

每次报告一个按键后调用一次 `input_sync()`，这样用户空间能区分不同的按键事件。

## 本章小结

事件报告的核心是 `input_event()` 函数，但对于按键事件通常用便利宏 `input_report_key()`。报告事件后必须调用 `input_sync()` 标记同步点，确保事件原子地传递给用户空间。按键代码定义在 `input-event-codes.h`，使用标准代码能保证跨平台兼容。

报告事件前要确保设备能力正确设置：`set_bit(EV_KEY, evbit)` 声明支持按键事件，`set_bit(KEY_ENTER, keybit)` 声明支持 Enter 键。忘记设置这些位图会导致事件被默默忽略。

下一章我们会讲解如何用 `delayed_work` 实现消抖，这是按键驱动必不可少的部分。

---

**相关文档**：
- [Input 子系统架构](02_input_architecture.md)
- [延时消抖](04_delayed_debounce.md)

**下一步：** 继续阅读 [04_delayed_debounce.md](04_delayed_debounce.md) 了解按键消抖的实现。
