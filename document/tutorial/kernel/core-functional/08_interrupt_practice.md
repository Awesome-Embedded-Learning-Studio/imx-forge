# 中断驱动实战指南：按键消抖到完整设备驱动

## 前言：从理论到实践

上一节我们讲了中断的理论和API。老实说，光看文档很难真正理解中断。只有当你真正写了一个驱动，处理了按键抖动、中断风暴、并发访问等问题，才算真正懂了。

这一节，我们写一个完整的按键中断驱动。它不只是「打印日志」那么简单，而是要：
1. 正确处理按键消抖
2. 使用工作队列做耗时处理
3. 通过`/dev`节点向用户空间报告按键事件
4. 正确处理并发访问

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 硬件 | GPIO按键 |

## 按键中断驱动的挑战

### 挑战1：按键抖动

机械按键在按下和释放时会产生抖动，电平会在短时间内多次跳变：

```
理想情况：
    ┌────────────
────┘            └────
    按下          释放

实际情况：
    ┌─┬┐┌──┐┌─┐
────┘ ││└─┘│└┼┘└───
      抖动
```

如果中断处理函数直接响应每一次跳变，就会产生大量虚假事件。

### 挑战2：中断上下文限制

中断处理函数不能睡眠，但按键事件可能需要：
* 防抖延时
* 通知用户空间
* 更新统计信息

这些操作不适合在中断上下文中做。

## 解决方案：中断 + 工作队列

我们使用「中断 + 工作队列」的架构：

```
GPIO中断 → 硬中断处理 → 工作队列 → 事件处理 → 用户空间
   ↓            ↓          ↓
 毫秒级      微秒级     可睡眠
```

## 完整驱动代码

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/workqueue.h>
#include <linux/spinlock.h>
#include <linux/wait.h>
#include <linux/sched/signal.h>
#include <linux/uaccess.h>
#include <linux/poll.h>

#define DRIVER_NAME "button_irq"
#define DEBOUNCE_MS 50

/* 按键事件 */
struct button_event {
    bool pressed;
    ktime_t timestamp;
};

/* 设备结构体 */
struct button_dev {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct gpio_desc *gpio;
    int irq;
    struct work_struct work;

    spinlock_t lock;
    bool last_state;
    bool pending;
    struct button_event event;

    wait_queue_head_t waitq;
    bool event_ready;

    /* 统计 */
    u64 press_count;
    u64 release_count;
    u64 irq_count;
};

static struct button_dev *button_devp;
static struct class *button_class;

/* 工作队列处理函数（进程上下文，可以睡眠） */
static void button_work_handler(struct work_struct *work)
{
    struct button_dev *dev = container_of(work, struct button_dev, work);
    bool state;
    unsigned long flags;
    ktime_t now;

    /* 延时消抖 */
    msleep_interruptible(DEBOUNCE_MS);

    /* 读取稳定后的状态 */
    state = gpiod_get_value(dev->gpio);
    now = ktime_get();

    spin_lock_irqsave(&dev->lock, flags);

    /* 只在状态变化时产生事件 */
    if (state != dev->last_state) {
        dev->last_state = state;
        dev->event.pressed = state;
        dev->event.timestamp = now;
        dev->event_ready = true;

        if (state) {
            dev->press_count++;
            pr_info("button: PRESSED\n");
        } else {
            dev->release_count++;
            pr_info("button: RELEASED\n");
        }

        /* 唤醒等待的读者 */
        wake_up_interruptible(&dev->waitq);
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}

/* 硬中断处理函数（中断上下文，必须快） */
static irqreturn_t button_irq_handler(int irq, void *dev_id)
{
    struct button_dev *dev = dev_id;

    dev->irq_count++;

    /* 调度工作队列，立即返回 */
    schedule_work(&dev->work);

    return IRQ_HANDLED;
}

/* 设备操作：打开 */
static int button_open(struct inode *inode, struct file *file)
{
    struct button_dev *dev =
        container_of(inode->i_cdev, struct button_dev, cdev);

    file->private_data = dev;
    pr_info("button: device opened\n");
    return 0;
}

/* 设备操作：读取按键事件 */
static ssize_t button_read(struct file *file,
                           char __user *buf,
                           size_t count,
                           loff_t *ppos)
{
    struct button_dev *dev = file->private_data;
    struct button_event event;
    unsigned long flags;
    int ret;

    /* 等待事件 */
    ret = wait_event_interruptible(dev->waitq, dev->event_ready);
    if (ret)
        return -ERESTARTSYS;

    spin_lock_irqsave(&dev->lock, flags);

    /* 复制事件 */
    event = dev->event;
    dev->event_ready = false;

    spin_unlock_irqrestore(&dev->lock, flags);

    /* 返回给用户 */
    if (copy_to_user(buf, &event, sizeof(event)))
        return -EFAULT;

    return sizeof(event);
}

/* 设备操作：poll */
static __poll_t button_poll(struct file *file,
                            poll_table *wait)
{
    struct button_dev *dev = file->private_data;
    __poll_t mask = 0;

    poll_wait(file, &dev->waitq, wait);

    if (dev->event_ready)
        mask |= EPOLLIN | EPOLLRDNORM;

    return mask;
}

static const struct file_operations button_fops = {
    .owner = THIS_MODULE,
    .open = button_open,
    .read = button_read,
    .poll = button_poll,
};

/* Probe函数 */
static int button_probe(struct platform_device *pdev)
{
    struct button_dev *dev;
    int ret;
    int irq_flags;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 获取GPIO */
    dev->gpio = devm_gpiod_get(&pdev->dev, NULL, GPIOD_IN);
    if (IS_ERR(dev->gpio)) {
        ret = PTR_ERR(dev->gpio);
        pr_err("button: failed to get GPIO: %d\n", ret);
        return ret;
    }

    /* 读取初始状态 */
    dev->last_state = gpiod_get_value(dev->gpio);

    /* 获取中断号 */
    dev->irq = gpiod_to_irq(dev->gpio);
    if (dev->irq < 0) {
        pr_err("button: failed to get IRQ\n");
        return dev->irq;
    }

    /* 初始化工作队列 */
    INIT_WORK(&dev->work, button_work_handler);

    /* 初始化自旋锁和等待队列 */
    spin_lock_init(&dev->lock);
    init_waitqueue_head(&dev->waitq);

    /* 配置中断标志：双边沿触发 */
    irq_flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;
    irq_flags |= IRQF_SHARED;  /* 允许共享 */

    /* 注册中断处理函数 */
    ret = devm_request_irq(&pdev->dev, dev->irq,
                           button_irq_handler,
                           irq_flags,
                           DRIVER_NAME, dev);
    if (ret) {
        pr_err("button: failed to request IRQ: %d\n", ret);
        return ret;
    }

    /* 分配设备号 */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, DRIVER_NAME);
    if (ret) {
        pr_err("button: failed to allocate chrdev region\n");
        return ret;
    }

    /* 初始化字符设备 */
    cdev_init(&dev->cdev, &button_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("button: failed to add cdev\n");
        goto err_unregister;
    }

    /* 创建设备类 */
    if (!button_class) {
        button_class = class_create(DRIVER_NAME);
        if (IS_ERR(button_class)) {
            ret = PTR_ERR(button_class);
            goto err_del_cdev;
        }
    }

    /* 创建设备节点 */
    dev->device = device_create(button_class, &pdev->dev,
                                dev->dev_num, NULL,
                                DRIVER_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    button_devp = dev;

    pr_info("button: device registered (GPIO=%d, IRQ=%d)\n",
            desc_to_gpio(dev->gpio), dev->irq);

    return 0;

err_destroy_class:
    class_destroy(button_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove函数 */
static int button_remove(struct platform_device *pdev)
{
    struct button_dev *dev = platform_get_drvdata(pdev);

    /* 取消工作队列 */
    cancel_work_sync(&dev->work);

    device_destroy(button_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("button: device unregistered\n");
    pr_info("button: stats: irqs=%llu, presses=%llu, releases=%llu\n",
            dev->irq_count, dev->press_count, dev->release_count);

    return 0;
}

/* 设备树匹配 */
static const struct of_device_id button_match[] = {
    { .compatible = "gpio-keys" },  /* 通用GPIO按键 */
    { .compatible = "imx,button-irq" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, button_match);

static struct platform_driver button_driver = {
    .probe = button_probe,
    .remove = button_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = button_match,
    },
};
module_platform_driver(button_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Button IRQ driver with debounce");
```

## 设备树配置

```dts
/* 添加到板级设备树 */
/ {
    button_irq {
        compatible = "imx,button-irq";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_button>;

        button-gpios = <&gpio1 18 GPIO_ACTIVE_LOW>;
    };

    pinctrl_button: button-grp {
        fsl,pins = <
            MX6UL_PAD_UART1_CTS_B__GPIO1_IO18  0x17059  /* GPIO1_IO18 */
        >;
    };
};
```

## 用户态测试程序

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <poll.h>
#include <time.h>

#define DEVICE "/dev/button_irq"

struct button_event {
    bool pressed;
    long long timestamp;  /* 纳秒时间戳 */
};

void print_timestamp(long long ns)
{
    time_t sec = ns / 1000000000LL;
    struct tm *tm = localtime(&sec);
    printf("%02d:%02d:%02d",
           tm->tm_hour, tm->tm_min, tm->tm_sec);
}

int main(void)
{
    int fd;
    struct button_event event;
    struct pollfd pfd;

    fd = open(DEVICE, O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Button monitor started. Press Ctrl+C to exit.\n");

    pfd.fd = fd;
    pfd.events = POLLIN;

    while (1) {
        int ret;

        /* 等待事件 */
        ret = poll(&pfd, 1, -1);
        if (ret < 0) {
            perror("poll");
            break;
        }

        /* 读取事件 */
        if (read(fd, &event, sizeof(event)) == sizeof(event)) {
            print_timestamp(event.timestamp);
            printf(" - Button %s\n", event.pressed ? "PRESSED" : "RELEASED");
        }
    }

    close(fd);
    return 0;
}
```

## 编译和测试

```bash
# 编译驱动
make

# 加载驱动
insmod button_irq_driver.ko

# 检查设备节点
ls -l /dev/button_irq

# 查看中断统计
cat /proc/interrupts | grep button

# 运行测试程序
./button_test

# 卸载驱动
rmmod button_irq_driver
```

## 常见问题排查

### 问题1：中断不触发

**症状**：按键没有任何反应，`/proc/interrupts`计数器不变。

**排查**：
1. 检查设备树配置是否正确
2. 检查GPIO是否正确配置为输入
3. 检查中断触发方式是否匹配硬件

### 问题2：中断风暴

**症状**：按键一次产生大量中断，系统卡顿。

**排查**：
1. 检查是否正确消抖
2. 检查中断处理函数是否清除了中断源
3. 使用`IRQF_ONESHOT`线程化中断

### 问题3：工作队列不执行

**症状**：中断处理函数被调用，但工作队列函数不执行。

**排查**：
1. 检查`INIT_WORK()`是否正确调用
2. 检查`schedule_work()`是否被调用
3. 检查工作队列是否被`cancel_work_sync()`取消

## 这一小节就到这里

按键中断驱动是一个很好的实战案例。它综合了：
* 中断处理（硬中断上下文）
* 工作队列（进程上下文）
* 并发控制（自旋锁）
* 用户空间通知（等待队列和poll）

掌握这个例子后，你就能处理大多数中断相关的驱动开发了。

下一节，我们学习阻塞I/O——另一种让进程等待的机制。

---

## 本章要点

1. **按键需要消抖**：使用工作队列延时处理，避免中断风暴。
2. **中断处理函数必须快**：只做最必要的事，耗时操作交给工作队列。
3. **`schedule_work()`调度工作队列**：从中断上下文切换到进程上下文。
4. **`cancel_work_sync()`清理工作队列**：确保工作队列完成后才返回。
5. **等待队列通知用户空间**：`wait_event_interruptible()` + `wake_up_interruptible()`。
6. **poll支持非阻塞访问**：`poll_wait()` + `EPOLLIN`。
