---
title: 中断机制
---

# Linux 7.0中断机制完整指南：从request_irq到线程化中断

## 前言：当硬件敲门时

前面我们讲了各种并发控制机制，但有一个特殊的「并发源」我们还没深入讲：**中断**。

中断之所以特殊，是因为它**不请自来**。无论你的代码在干什么，无论你拿着什么锁，一旦硬件中断来了，CPU必须立刻响应。

这就像你在专心工作的时候，老板突然敲门。你必须立刻放下手头的事去应付老板。如果老板让你做的事也需要你之前的工作资源，那就麻烦了——你的工作状态可能还没保存好，就被打断了。

在内核里，这种情况更严重。中断处理程序（ISR）在特殊上下文中运行，有很多限制。如果处理不当，轻则功能异常，重则系统死锁。

这一节，我们深入理解Linux的中断机制，以及如何正确地处理中断。

## 环境：基于Linux 7.0-rc4

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.0-rc4 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/interrupt.h` |

## 中断的基本概念

### 什么是中断？

中断是硬件通知CPU「有事情发生了」的机制。当外设（如网卡、串口、定时器）需要CPU注意时，它会触发一个中断信号。CPU收到信号后，暂停当前执行的任务，跳转到中断服务程序（ISR）执行。

### 中断的特点

1. **异步性**：中断随时可能发生，无法预测
2. **优先性**：中断优先级高于普通进程
3. **上下文特殊**：ISR运行在中断上下文中，有很多限制

### 中断的分类

在Linux中，中断通常被分为两部分：

* **上半部（Top Half）**：真正的ISR，在关中断的情况下执行，必须快速完成
* **下半部（Bottom Half）**：延迟处理部分，在开中断的情况下执行

为什么要分两部分？

因为ISR必须尽快完成，否则会：
* 阻塞其他中断
* 增加系统延迟
* 可能导致丢失中断

## 注册中断：request_irq

在驱动中注册中断处理函数的API是`request_irq()`：

```c
int request_irq(unsigned int irq,
                irq_handler_t handler,
                unsigned long flags,
                const char *name,
                void *dev_id);
```

### 参数说明

| 参数 | 描述 |
| --- | --- |
| `irq` | 中断号（从设备树或平台数据获取） |
| `handler` | 中断处理函数 |
| `flags` | 中断标志位（见下表） |
| `name` | 中断名称（出现在/proc/interrupts中） |
| `dev_id` | 设备ID（用于共享中断和释放） |

### 返回值

* `0`：成功
* 负值：错误码（如`-EBUSY`表示中断已被占用）

### 中断标志（flags）

```c
/* 触发方式 */
#define IRQF_TRIGGER_NONE    0x00000000  /* 无触发方式 */
#define IRQF_TRIGGER_RISING  0x00000001  /* 上升沿触发 */
#define IRQF_TRIGGER_FALLING 0x00000002  /* 下降沿触发 */
#define IRQF_TRIGGER_HIGH    0x00000004  /* 高电平触发 */
#define IRQF_TRIGGER_LOW     0x00000008  /* 低电平触发 */
#define IRQF_TRIGGER_MASK    0x0000000f  /* 触发方式掩码 */

/* 处理方式 */
#define IRQF_SHARED          0x00000080  /* 共享中断 */
#define IRQF_PROBE_SHARED    0x00000100  /* 探测共享中断 */

/* 执行方式 */
#define IRQF_ONESHOT         0x00002000  /* 一次性中断（线程化） */
#define IRQF_NO_THREAD       0x00004000  /* 不能线程化 */
#define IRQF_PERCPU          0x00000400  /* 每CPU中断 */
#define IRQF_NOBALANCING     0x00000800  /* 不进行中断平衡 */

/* 新增标志（Linux 7.0） */
#define IRQF_NO_AUTOEN       0x00800000  /* 不自动使能中断 */
#define IRQF_COND_ONESHOT    0x02000000  /* 条件一次性中断 */
```

### 中断处理函数

中断处理函数的签名是固定的：

```c
irqreturn_t handler(int irq, void *dev_id);
```

返回值：

* `IRQ_NONE`：不是这个设备的中断
* `IRQ_HANDLED`：中断已处理
* `IRQ_WAKE_THREAD`：唤醒中断线程

## 中断处理示例

### 基本的中断注册

```c
#include <linux/interrupt.h>
#include <linux/gpio.h>
#include <linux/of_gpio.h>
#include <linux/interrupt.h>

#define GPIO_IRQ_PIN  123  /* 假设GPIO 123 */

static int gpio_irq = -1;
static int gpio_pin = -1;

/* 中断处理函数 */
static irqreturn_t gpio_irq_handler(int irq, void *dev_id)
{
    pr_info("GPIO interrupt triggered!\n");

    /* 处理中断... */

    return IRQ_HANDLED;
}

static int my_probe(struct platform_device *pdev)
{
    int ret;
    int irq_flags;

    /* 从设备树获取GPIO */
    gpio_pin = of_get_named_gpio(pdev->dev.of_node, "irq-gpio", 0);
    if (!gpio_is_valid(gpio_pin)) {
        pr_err("Invalid IRQ GPIO\n");
        return gpio_pin;
    }

    /* 请求GPIO */
    ret = devm_gpio_request_one(&pdev->dev, gpio_pin,
                                 GPIOF_IN, "irq-gpio");
    if (ret) {
        pr_err("Failed to request GPIO\n");
        return ret;
    }

    /* 获取中断号 */
    gpio_irq = gpio_to_irq(gpio_pin);
    if (gpio_irq < 0) {
        pr_err("Failed to get IRQ number\n");
        return gpio_irq;
    }

    /* 配置中断标志：下降沿触发 */
    irq_flags = IRQF_TRIGGER_FALLING;

    /* 注册中断处理函数 */
    ret = devm_request_irq(&pdev->dev, gpio_irq, gpio_irq_handler,
                           irq_flags, "my-gpio-irq", NULL);
    if (ret) {
        pr_err("Failed to request IRQ: %d\n", ret);
        return ret;
    }

    pr_info("IRQ registered: gpio=%d, irq=%d\n", gpio_pin, gpio_irq);
    return 0;
}
```

### 使用设备树

在设备树中配置中断：

```dts
/* 设备树节点 */
my-device {
    compatible = "imx,my-device";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_my_device>;

    /* 中断配置 */
    interrupt-parent = <&gpio1>;
    interrupts = <18 IRQ_TYPE_EDGE_FALLING>;  /* GPIO1_18, 下降沿 */
};
```

驱动中获取：

```c
static int my_probe(struct platform_device *pdev)
{
    int irq;
    int ret;

    /* 从设备树获取中断 */
    irq = platform_get_irq(pdev, 0);
    if (irq < 0) {
        return irq;
    }

    /* 注册中断处理函数 */
    ret = devm_request_irq(&pdev->dev, irq, my_irq_handler,
                           IRQF_TRIGGER_FALLING,
                           pdev->name, NULL);
    if (ret) {
        pr_err("Failed to request IRQ\n");
        return ret;
    }

    return 0;
}
```

## 释放中断

使用`free_irq()`或`devm_free_irq()`释放中断：

```c
/* 手动释放 */
free_irq(gpio_irq, NULL);

/* 托管释放（devm_版本自动处理） */
/* devm_request_irq()在驱动卸载时自动调用devm_free_irq() */
```

**⚠️ 注意**：

`dev_id`参数必须与注册时一致，否则会释放失败或导致问题。

## 共享中断

多个设备可以共享同一个中断线（如PCI设备）。使用`IRQF_SHARED`标志注册：

```c
static irqreturn_t dev_a_handler(int irq, void *dev_id)
{
    struct my_device *dev = dev_id;

    /* 检查是否真的是这个设备的中断 */
    if (!is_my_interrupt(dev))
        return IRQ_NONE;  /* 不是我的，返回IRQ_NONE */

    /* 处理中断 */
    handle_interrupt(dev);

    return IRQ_HANDLED;
}

static int my_probe(struct platform_device *pdev)
{
    struct my_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 注册共享中断 */
    ret = devm_request_irq(&pdev->dev, irq, dev_a_handler,
                           IRQF_SHARED,  /* 共享标志 */
                           pdev->name, dev);  /* dev作为dev_id */
    if (ret) {
        pr_err("Failed to request shared IRQ\n");
        return ret;
    }

    return 0;
}
```

**共享中断的规则**：

1. 必须使用`IRQF_SHARED`标志
2. 每个设备必须有唯一的`dev_id`
3. 中断处理函数必须检查是否真的是自己的中断
4. 如果不是自己的中断，返回`IRQ_NONE`

## 线程化中断

Linux支持将中断处理程序放在内核线程中执行，而不是在硬中断上下文中。这叫做**线程化中断**。

### 为什么需要线程化中断？

* 硬中断上下文限制太多（不能睡眠、不能调度）
* 某些中断处理程序需要较长时间
* 可以降低中断延迟，提高系统响应性

### 如何使用线程化中断？

使用`IRQF_ONESHOT`标志：

```c
/* 硬中断处理函数（尽可能快） */
static irqreturn_t my_hard_irq(int irq, void *dev_id)
{
    /* 只做最必要的处理 */
    pr_info("Hard IRQ\n");

    /* 返回IRQ_WAKE_THREAD唤醒线程 */
    return IRQ_WAKE_THREAD;
}

/* 线程化中断处理函数（可以睡眠） */
static irqreturn_t my_thread_fn(int irq, void *dev_id)
{
    struct my_device *dev = dev_id;

    /* 这里可以睡眠、获取互斥体等 */
    msleep(10);  /* 可以睡眠！ */

    pr_info("Threaded IRQ handler\n");
    return IRQ_HANDLED;
}

static int my_probe(struct platform_device *pdev)
{
    struct my_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 注册线程化中断 */
    ret = request_threaded_irq(dev->irq, my_hard_irq, my_thread_fn,
                               IRQF_ONESHOT,
                               "my-threaded-irq", dev);
    if (ret) {
        pr_err("Failed to request threaded IRQ\n");
        return ret;
    }

    return 0;
}
```

### `IRQF_ONESHOT`的作用

`IRQF_ONESHOT`确保：
1. 硬中断处理完成后，中断线才会重新使能
2. 线程化处理函数执行期间，中断线保持禁用
3. 防止中断风暴

## 禁止/启用中断

在某些情况下，你可能需要临时禁止或启用中断：

### 本地中断控制

```c
unsigned long flags;

/* 禁止本地中断并保存状态 */
local_irq_save(flags);

/* 临界区：本地中断被禁用 */

/* 恢复之前的中断状态 */
local_irq_restore(flags);

/* 或者简单地禁止/启用（不保存状态） */
local_irq_disable();
/* 临界区 */
local_irq_enable();
```

### 特定中断控制

```c
/* 禁止特定中断 */
disable_irq(irq);

/* 等待正在执行的中断完成后再禁用 */
disable_irq_sync(irq);

/* 启用中断 */
enable_irq(irq);
```

**⚠️ 注意**：

* `disable_irq_sync()`不能在中断上下文中调用
* 调用`disable_irq()`后，必须确保对应的`enable_irq()`会被调用

## 中断上下文的限制

中断处理函数运行在特殊的上下文中，有很多限制：

### 不能做的事

| 操作 | 原因 |
| --- | --- |
| 睡眠（`msleep`等） | 中断上下文不能调度 |
| 获取互斥体（`mutex_lock`） | 可能睡眠 |
| 访问用户空间（`copy_from_user`） | 页错误可能睡眠 |
| 分配内存（`GFP_KERNEL`） | 可能睡眠 |

### 能做的事

| 操作 | 说明 |
| --- | --- |
| 自旋锁 | 可以，但要注意`irqsave`版本 |
| 原子操作 | 可以 |
| `GFP_ATOMIC`分配 | 可以，不睡眠 |
| 忙等待（`udelay`） | 可以，但尽量短 |

## 调试中断

### 查看中断统计

```bash
# 查看系统中断信息
$ cat /proc/interrupts

# 查看特定中断详情
$ cat /proc/irq/<irq>/spurious
```

### 常见问题

1. **中断不触发**
   * 检查设备树配置
   * 检查GPIO配置
   * 检查中断触发方式

2. **中断风暴**
   * 中断处理函数返回`IRQ_HANDLED`但未清除中断源
   * 检查硬件是否正确清除中断

3. **系统死锁**
   * 中断处理函数中获取了被进程持有的锁
   * 使用`spin_lock_irqsave`而不是`spin_lock`

## 这一小节就到这里

Linux的中断机制是一个复杂但重要的主题。记住几个关键点：

1. **中断必须尽快处理**，耗时操作放下半部
2. **共享中断必须返回`IRQ_NONE`**如果不是自己的中断
3. **线程化中断可以睡眠**，用`IRQF_ONESHOT`
4. **中断上下文不能睡眠**，使用`GFP_ATOMIC`和自旋锁

下一节，我们写一个完整的中断驱动示例。

---

## 本章要点

1. **`request_irq()`注册中断**，`free_irq()`释放中断。
2. **中断标志很重要**：`IRQF_SHARED`用于共享，`IRQF_ONESHOT`用于线程化。
3. **中断处理函数返回值**：`IRQ_NONE`（不是我的），`IRQ_HANDLED`（已处理）。
4. **线程化中断分为两部分**：硬中断（快）+线程函数（可睡眠）。
5. **中断上下文不能睡眠**，不能用互斥体，只能用自旋锁。
6. **调试中断用`/proc/interrupts`**，检查触发方式和统计信息。
