---
title: 时间管理
---

# 从0开始理解Linux时间管理：jiffies到hrtimer的演进

## 前言：内核中的时间是什么？

在用户空间编程时，我们习惯了用`sleep()`、`usleep()`这样的函数来等待，或者用`gettimeofday()`来获取当前时间。但在内核里，这些都不能用。

为什么？

因为内核是整个系统的管理者，它需要更高精度、更低开销的时间管理机制。而且，内核中的时间管理涉及到底层的硬件定时器、调度器、中断处理，比用户空间复杂得多。

老实说，我刚开始写内核驱动的时候，对时间管理一窍不通。我以为直接调用个`delay()`就行，结果编译都过不了。后来我花了很长时间才理解：**内核中的时间管理是一套完整的体系，从硬件定时器到软件定时器，层层抽象。**

这一节，我们从最基础的`jiffies`开始，逐步理解内核是如何管理时间的。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/jiffies.h`, `include/linux/timer.h` |

## jiffies：内核的心跳

内核中有一个全局变量，叫`jiffies`。它记录了系统启动以来经过的「滴答数」。

你可以把它理解为内核的「心跳计数器」。每隔一段时间（这个间隔由`HZ`决定），硬件定时器会产生一个中断，`jiffies`就会加1。

### HZ：每秒的滴答数

`HZ`是一个宏定义，表示每秒有多少次滴答。在我们的ARM Linux系统中，通常`HZ=100`或`HZ=200`。

```c
/* 常见的HZ值 */
#define HZ 100  /* 每秒100次滴答，即每10ms一次 */
#define HZ 200  /* 每秒200次滴答，即每5ms一次 */
#define HZ 1000 /* 每秒1000次滴答，即每1ms一次 */
```

**为什么不能无限提高HZ？**

HZ越高，时间精度越高，但开销也越大：
* 更多的定时器中断
* 更频繁的调度器运行
* 更多的功耗

### jiffies的精度限制

由于`jiffies`是基于滴答数的，它的精度受限于HZ值。

| HZ | 滴答间隔 | 精度 |
|----|----------|------|
| 100 | 10ms | 10ms |
| 200 | 5ms | 5ms |
| 1000 | 1ms | 1ms |

如果你的应用需要微秒级的精度，`jiffies`就不够用了。这时候需要用高精度定时器（hrtimer）。

### 时间单位转换

内核提供了一组宏来转换时间单位：

```c
#include <linux/jiffies.h>

/* 毫秒转jiffies */
unsigned long j = msecs_to_jiffies(100);  /* 100ms */

/* 秒转jiffies */
j = msecs_to_jiffies(1000);  /* 1秒 */

/* 微秒转jiffies（注意精度损失） */
j = usecs_to_jiffies(1000);  /* 1ms */

/* jiffies转毫秒（用于打印） */
unsigned int ms = jiffies_to_msecs(j);
```

### jiffies的回绕问题

`jiffies`是一个32位或64位的无符号整数。当它达到最大值后，会回绕到0。

```
32位jiffies：
0xFFFFFFFF → 0x00000000

大约每49.7天回绕一次（HZ=100时）
```

**这就是问题**：如果你直接比较两个`jiffies`值，可能会在回绕时出错。

```c
/* ❌ 错误的比较方式 */
if (timeout < jiffies) {
    /* 在回绕时，这个判断会出错！ */
}

/* ✓ 正确的比较方式 */
if (time_after(jiffies, timeout)) {
    /* 这个宏正确处理了回绕 */
}

if (time_before(jiffies, timeout)) {
    /* 同样正确 */
}
```

**时间比较宏**：

| 宏 | 描述 |
| --- | --- |
| `time_after(a, b)` | `a > b`（正确处理回绕） |
| `time_before(a, b)` | `a < b`（正确处理回绕） |
| `time_after_eq(a, b)` | `a >= b` |
| `time_before_eq(a, b)` | `a <= b` |

## 内核定时器：在指定时间执行回调

内核定时器是内核中最常用的延时执行机制。它允许你在指定的时间后执行一个回调函数。

### 定时器的结构

在Linux 7.0中，定时器用`timer_list`结构体表示：

```c
struct timer_list {
    /* 内部字段 */
    struct hlist_node entry;
    unsigned long expires;
    void (*function)(struct timer_list *timer);
    u32 flags;
    /* ... */
};
```

### Linux 7.0的重大变化

**⚠️ 重要**：如果你有旧的4.x内核代码，需要注意以下变化：

1. **`init_timer()`已废弃**，必须使用`timer_setup()`
2. **`data`字段已移除**，必须使用`from_timer()`宏获取包含结构体
3. **`del_timer_sync()`被`timer_delete_sync()`替代**（虽然旧名字仍可用）

### 新的定时器API

| 函数 | 描述 |
| --- | --- |
| `timer_setup(timer, callback, flags)` | 初始化定时器 |
| `void (*callback)(struct timer_list *)` | 定时器回调函数签名 |
| `add_timer(timer)` | 激活定时器 |
| `mod_timer(timer, expires)` | 修改定时器的过期时间 |
| `timer_delete(timer)` | 删除定时器（可能返回还在运行） |
| `timer_delete_sync(timer)` | 删除定时器并等待回调完成 |
| `timer_pending(timer)` | 检测定时器是否 pending |

### 定时器标志

```c
#define TIMER_DEFERRABLE  0x00080000  /* 可延迟定时器 */
#define TIMER_PINNED      0x00100000  /* 固定在当前CPU */
#define TIMER_IRQSAFE     0x00200000  /* 中断安全定时器 */
```

* **TIMER_DEFERRABLE**：系统空闲时不会唤醒CPU
* **TIMER_PINNED**：定时器总是在指定的CPU上执行
* **TIMER_IRQSAFE**：回调在中断关闭的情况下执行

### 定时器示例

```c
#include <linux/timer.h>
#include <linux/jiffies.h>

struct my_device {
    struct timer_list timer;
    int counter;
    /* ... 其他成员 ... */
};

/* 定时器回调函数 */
static void my_timer_callback(struct timer_list *timer)
{
    /* 使用container_of或from_timer获取包含结构体 */
    struct my_device *dev = from_timer(dev, timer, timer);

    dev->counter++;
    pr_info("Timer fired, counter = %d\n", dev->counter);

    /* 如果需要周期性执行，重新设置定时器 */
    mod_timer(&dev->timer, jiffies + msecs_to_jiffies(1000));
}

/* 初始化定时器 */
static int my_device_init(struct my_device *dev)
{
    /* ✓ Linux 7.0的正确方式 */
    timer_setup(&dev->timer, my_timer_callback, 0);

    /* 设置1秒后过期 */
    dev->timer.expires = jiffies + msecs_to_jiffies(1000);

    /* 激活定时器 */
    add_timer(&dev->timer);

    return 0;
}

/* 清理定时器 */
static void my_device_cleanup(struct my_device *dev)
{
    /* 删除定时器并等待回调完成 */
    timer_delete_sync(&dev->timer);
}
```

### 旧API vs 新API对比

```c
/* ❌ 旧API（Linux 4.14之前） */
struct timer_list my_timer;

void callback(unsigned long data)
{
    struct my_device *dev = (struct my_device *)data;
    /* ... */
}

init_timer(&my_timer);
my_timer.data = (unsigned long)dev;
my_timer.function = callback;
my_timer.expires = jiffies + msecs_to_jiffies(1000);
add_timer(&my_timer);

/* ✓ 新API（Linux 4.14+，包括7.0） */
struct timer_list my_timer;

void callback(struct timer_list *timer)
{
    struct my_device *dev = from_timer(dev, timer, timer);
    /* ... */
}

timer_setup(&my_timer, callback, 0);
my_timer.expires = jiffies + msecs_to_jiffies(1000);
add_timer(&my_timer);
```

## 高精度定时器：hrtimer

当你需要微秒甚至纳秒级的精度时，`jiffies`和`timer_list`就不够用了。这时候需要用高精度定时器（hrtimer）。

### hrtimer的特点

* 纳秒级精度
* 基于高精度硬件时钟（如ARM的定时器）
* 不依赖HZ配置

### hrtimer API（简介）

```c
#include <linux/hrtimer.h>

enum hrtimer_restart callback(struct hrtimer *timer);

struct hrtimer {
    /* ... */
};

/* 初始化hrtimer */
void hrtimer_init(struct hrtimer *timer, clockid_t clock_id,
                 enum hrtimer_mode mode);

/* 启动hrtimer */
void hrtimer_start(struct hrtimer *timer, ktime_t time,
                  const enum hrtimer_mode mode);

/* 取消hrtimer */
int hrtimer_cancel(struct hrtimer *timer);
```

**clock_id选项**：

* `CLOCK_MONOTONIC`：单调时钟，不受系统时间调整影响
* `CLOCK_REALTIME`：实时时钟，可能被NTP调整
* `CLOCK_BOOTTIME`：包含休眠时间的单调时钟

**⚠️ 注意**：hrtimer的使用比较复杂，通常驱动代码用`timer_list`就够了。只有在需要极高精度时才考虑hrtimer。

## 短延迟：忙等待

有时候，你需要极短的延迟（比如微秒级），而且不需要很精确。内核提供了一些忙等待函数：

```c
#include <linux/delay.h>

/* 忙等待指定的纳秒/微秒/毫秒数 */
void ndelay(unsigned long nsecs);  /* 纳秒延迟 */
void udelay(unsigned long usecs);  /* 微秒延迟 */
void mdelay(unsigned long msecs);  /* 毫秒延迟 */
```

**⚠️ 注意**：

* 这些函数会**占用CPU**，是忙等待
* 只在极短延迟时使用（通常小于1ms）
* 较长延迟应该用定时器或睡眠函数

## 睡眠延迟：让出CPU

如果你的延迟时间较长（毫秒级或更长），应该让出CPU，让其他进程运行。

### 可中断睡眠

```c
#include <linux/delay.h>

/* 睡眠指定毫秒数（可被信号中断） */
void msleep(unsigned int msecs);

/* 睡眠指定毫秒数（不可中断） */
void msleep_interruptible(unsigned int msecs);

/* 睡眠指定微秒数（上限2000us） */
void usleep_range(unsigned long min, unsigned long max);
```

### usleep_range：推荐的选择

`usleep_range()`是现代内核推荐的高精度睡眠函数：

```c
/* 睡眠100-150微秒 */
usleep_range(100, 150);
```

它给出一个范围，让调度器可以在范围内选择最佳唤醒时间，有助于省电和减少调度开销。

### 等待事件

有时候，你需要等待某个条件成立，而不是固定的延迟。这时候用等待队列：

```c
#include <linux/wait.h>

/* 等待条件成立，超时时间为jiffies */
wait_event_timeout(wait_queue_head_t wq, condition, timeout);

/* 可中断版本 */
wait_event_interruptible_timeout(wq, condition, timeout);
```

## 实战：在驱动中使用定时器

让我们用一个实际例子来总结这些时间管理机制。

### 场景：LED闪烁驱动

```c
#include <linux/module.h>
#include <linux/timer.h>
#include <linux/gpio/consumer.h>
#include <linux/platform_device.h>

struct blink_led {
    struct gpio_desc *gpio;
    struct timer_list timer;
    bool led_on;
    unsigned long interval_ms;
};

static void blink_timer_callback(struct timer_list *timer)
{
    struct blink_led *bled = from_timer(bled, timer, timer);

    /* 切换LED状态 */
    bled->led_on = !bled->led_on;
    gpiod_set_value(bled->gpio, bled->led_on);

    /* 重新设置定时器 */
    mod_timer(&bled->timer,
              jiffies + msecs_to_jiffies(bled->interval_ms));
}

static int blink_led_probe(struct platform_device *pdev)
{
    struct blink_led *bled;

    bled = devm_kzalloc(&pdev->dev, sizeof(*bled), GFP_KERNEL);
    if (!bled)
        return -ENOMEM;

    /* 获取GPIO */
    bled->gpio = devm_gpiod_get(&pdev->dev, NULL, GPIOD_OUT_LOW);
    if (IS_ERR(bled->gpio))
        return PTR_ERR(bled->gpio);

    /* 初始化定时器 */
    bled->interval_ms = 500;  /* 500ms闪烁 */
    bled->led_on = false;
    timer_setup(&bled->timer, blink_timer_callback, 0);

    /* 启动定时器 */
    bled->timer.expires = jiffies + msecs_to_jiffies(bled->interval_ms);
    add_timer(&bled->timer);

    platform_set_drvdata(pdev, bled);
    pr_info("Blink LED driver loaded\n");

    return 0;
}

static int blink_led_remove(struct platform_device *pdev)
{
    struct blink_led *bled = platform_get_drvdata(pdev);

    /* 删除定时器 */
    timer_delete_sync(&bled->timer);

    pr_info("Blink LED driver unloaded\n");
    return 0;
}

/* ... platform_driver定义 ... */
```

## 时间管理决策树

```
需要延时/定时？
├─ 极短延迟（<10微秒）
│  └─ 用 ndelay/udelay（忙等待）
├─ 短延迟（10us - 1ms）
│  └─ 用 usleep_range（睡眠）
├─ 中等延迟（1ms - 1秒）
│  └─ 用 msleep 或 timer_list
├─ 长延迟（>1秒）
│  └─ 用 timer_list 或 wait_queue
└─ 高精度需求（<1us）
   └─ 用 hrtimer
```

## 这一小节就到这里

Linux内核的时间管理是一套完整的体系，从基于滴答的`jiffies`，到高精度的`hrtimer`，满足不同场景的需求。

对于大多数驱动代码：
* **短延迟**用`usleep_range()`
* **定时任务**用`timer_list`
* **极高精度**才用`hrtimer`

下一节，我们会在实战中深入使用定时器，写一个完整的定时器驱动示例。

---

## 本章要点

1. **jiffies是内核的心跳计数器**，精度受HZ限制（通常5-10ms）。
2. **时间比较必须用宏**（`time_after`等），因为jiffies会回绕。
3. **Linux 7.0使用新的timer API**：`timer_setup()`替代`init_timer()`，`from_timer()`替代`data`字段。
4. **`timer_delete_sync()`替代`del_timer_sync()`**，确保回调完成后才返回。
5. **忙等待（udelay）用于极短延迟**，睡眠（usleep_range/msleep）用于较长延迟。
6. **hrtimer提供纳秒级精度**，但使用复杂，大多数驱动用timer_list足够。
