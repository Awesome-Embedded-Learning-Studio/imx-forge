# 异步通知实战指南：让硬件主动找你

## 前言：从「轮询」到「通知」

前面我们讲了阻塞I/O（进程等待）和poll（应用程序轮询）。但还有第三种模式：**异步通知**。

异步通知的思想是：**当有事件发生时，驱动主动通知应用程序**，而不是应用程序不停地查询。

这就像快递 delivery：
* **阻塞I/O**：你在家门口等快递，什么都做不了
* **poll**：你每隔10分钟去看一眼快递有没有到
* **异步通知**：快递到了给你打电话，你收到通知后再去取

显然，异步通知是最优雅的方式——应用程序可以专心做别的事，只在有事件时才被通知。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/fs.h` |

## 异步通知的基本概念

### SIGIO信号

Linux使用`SIGIO`信号（或`SIGPOLL`）来实现异步I/O通知。当文件描述符上有事件发生时，内核会向注册过的进程发送信号。

### FASYNC标志

应用程序通过`fcntl()`设置`FASYNC`标志来启用异步通知：

```c
/* 启用异步通知 */
int flags = fcntl(fd, F_GETFL);
fcntl(fd, F_SETFL, flags | FASYNC);

/* 设置信号拥有者 */
fcntl(fd, F_SETOWN, getpid());
```

## 驱动中的实现

### 驱动需要实现的操作

1. **fasync操作**：管理异步通知列表
2. **事件发生时**：调用`kill_fasync()`发送信号

### 相关数据结构

```c
struct fasync_struct {
    spinlock_t      lock;
    int             magic;
    int             fa_fd;
    struct file     *fa_file;
    struct rcu_head fa_rcu;
    struct fasync_struct *fa_next; /* singly linked list */
    /* ... */
};
```

### 相关函数

```c
/* 管理异步通知列表 */
int fasync_helper(int fd, struct file *filp, int on,
                  struct fasync_struct **fapp);

/* 发送信号给注册的进程 */
void kill_fasync(struct fasync_struct **fp, int sig, int band);
```

## 完整示例：带异步通知的按键驱动

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/fcntl.h>

#define DRIVER_NAME "async_demo"
#define DEVICE_NAME "async_button"

struct async_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct gpio_desc *gpio;
    int irq;

    spinlock_t lock;
    bool button_state;
    bool event_pending;

    struct fasync_struct *async_queue;

    /* 统计 */
    u64 press_count;
    u64 notify_count;
};

static struct async_device *async_devp;
static struct class *async_class;

/* fasync操作 */
static int async_fasync(int fd, struct file *file, int on)
{
    struct async_device *dev = file->private_data;

    /* fasync_helper管理异步通知列表 */
    return fasync_helper(fd, file, on, &dev->async_queue);
}

/* 发送信号给用户空间 */
static void send_signal(struct async_device *dev)
{
    /* 发送SIGIO信号，表示有数据可读 */
    kill_fasync(&dev->async_queue, SIGIO, POLL_IN);

    dev->notify_count++;
    pr_info("async: signal sent (total: %llu)\n", dev->notify_count);
}

/* 中断处理函数 */
static irqreturn_t async_irq_handler(int irq, void *dev_id)
{
    struct async_device *dev = dev_id;
    bool new_state;
    unsigned long flags;

    spin_lock_irqsave(&dev->lock, flags);

    /* 读取按键状态 */
    new_state = gpiod_get_value(dev->gpio);

    /* 只在状态变化时处理 */
    if (new_state != dev->button_state) {
        dev->button_state = new_state;
        dev->event_pending = true;

        if (new_state) {
            dev->press_count++;
        }

        /* 发送异步通知 */
        send_signal(dev);
    }

    spin_unlock_irqrestore(&dev->lock, flags);

    return IRQ_HANDLED;
}

/* 设备操作：打开 */
static int async_open(struct inode *inode, struct file *file)
{
    struct async_device *dev =
        container_of(inode->i_cdev, struct async_device, cdev);

    file->private_data = dev;
    pr_info("async: device opened\n");
    return 0;
}

/* 设备操作：读取按键状态 */
static ssize_t async_read(struct file *file,
                          char __user *buf,
                          size_t count,
                          loff_t *ppos)
{
    struct async_device *dev = file->private_data;
    bool state;
    unsigned long flags;

    if (count < sizeof(bool))
        return -EINVAL;

    spin_lock_irqsave(&dev->lock, flags);
    state = dev->button_state;
    dev->event_pending = false;
    spin_unlock_irqrestore(&dev->lock, flags);

    if (copy_to_user(buf, &state, sizeof(state)))
        return -EFAULT;

    return sizeof(state);
}

/* 设备操作：ioctl（获取统计） */
static long async_ioctl(struct file *file,
                        unsigned int cmd, unsigned long arg)
{
    struct async_device *dev = file->private_data;

    switch (cmd) {
    case 0:  /* 获取按压次数 */
        if (copy_to_user((void __user *)arg, &dev->press_count,
                         sizeof(u64)))
            return -EFAULT;
        return 0;
    default:
        return -ENOTTY;
    }
}

static const struct file_operations async_fops = {
    .owner = THIS_MODULE,
    .open = async_open,
    .read = async_read,
    .unlocked_ioctl = async_ioctl,
    .fasync = async_fasync,  /* fasync操作 */
};

/* Probe函数 */
static int async_probe(struct platform_device *pdev)
{
    struct async_device *dev;
    int ret;
    int irq_flags;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 获取GPIO */
    dev->gpio = devm_gpiod_get(&pdev->dev, NULL, GPIOD_IN);
    if (IS_ERR(dev->gpio)) {
        ret = PTR_ERR(dev->gpio);
        pr_err("async: failed to get GPIO: %d\n", ret);
        return ret;
    }

    /* 读取初始状态 */
    dev->button_state = gpiod_get_value(dev->gpio);

    /* 获取中断号 */
    dev->irq = gpiod_to_irq(dev->gpio);
    if (dev->irq < 0) {
        pr_err("async: failed to get IRQ\n");
        return dev->irq;
    }

    /* 初始化自旋锁 */
    spin_lock_init(&dev->lock);

    /* 配置中断标志：双边沿触发 */
    irq_flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;

    /* 注册中断处理函数 */
    ret = devm_request_irq(&pdev->dev, dev->irq,
                           async_irq_handler,
                           irq_flags,
                           DRIVER_NAME, dev);
    if (ret) {
        pr_err("async: failed to request IRQ: %d\n", ret);
        return ret;
    }

    /* 分配设备号 */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, DRIVER_NAME);
    if (ret) {
        pr_err("async: failed to allocate chrdev region\n");
        return ret;
    }

    /* 初始化字符设备 */
    cdev_init(&dev->cdev, &async_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("async: failed to add cdev\n");
        goto err_unregister;
    }

    /* 创建设备类 */
    if (!async_class) {
        async_class = class_create(DRIVER_NAME);
        if (IS_ERR(async_class)) {
            ret = PTR_ERR(async_class);
            goto err_del_cdev;
        }
    }

    /* 创建设备节点 */
    dev->device = device_create(async_class, &pdev->dev,
                                dev->dev_num, NULL,
                                DEVICE_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    async_devp = dev;

    pr_info("async: device registered (GPIO=%d, IRQ=%d)\n",
            desc_to_gpio(dev->gpio), dev->irq);

    return 0;

err_destroy_class:
    class_destroy(async_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove函数 */
static int async_remove(struct platform_device *pdev)
{
    struct async_device *dev = platform_get_drvdata(pdev);

    device_destroy(async_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("async: device unregistered\n");
    pr_info("async: stats: presses=%llu, notifies=%llu\n",
            dev->press_count, dev->notify_count);

    return 0;
}

/* 设备树匹配 */
static const struct of_device_id async_match[] = {
    { .compatible = "gpio-keys" },  /* 通用GPIO按键 */
    { .compatible = "imx,async-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, async_match);

static struct platform_driver async_driver = {
    .probe = async_probe,
    .remove = async_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = async_match,
    },
};
module_platform_driver(async_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Async notification demo driver");
```

## 用户态测试程序

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stdbool.h>
#include <errno.h>
#include <string.h>

#define DEVICE "/dev/async_button"

/* 信号处理标志 */
static volatile sig_atomic_t signal_received = 0;

/* SIGIO信号处理函数 */
static void sigio_handler(int signo)
{
    signal_received = 1;
}

int main(void)
{
    int fd;
    struct sigaction sa;
    bool state;
    ssize_t ret;

    /* 打开设备 */
    fd = open(DEVICE, O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    /* 设置信号处理函数 */
    sa.sa_flags = SA_RESTART;
    sa.sa_handler = sigio_handler;
    sigemptyset(&sa.sa_mask);

    if (sigaction(SIGIO, &sa, NULL) < 0) {
        perror("sigaction");
        close(fd);
        return 1;
    }

    /* 设置文件描述符的拥有者（接收信号） */
    if (fcntl(fd, F_SETOWN, getpid()) < 0) {
        perror("fcntl F_SETOWN");
        close(fd);
        return 1;
    }

    /* 启用异步通知 */
    int flags = fcntl(fd, F_GETFL);
    if (fcntl(fd, F_SETFL, flags | O_ASYNC) < 0) {
        perror("fcntl F_SETFL O_ASYNC");
        close(fd);
        return 1;
    }

    printf("Async notification demo started.\n");
    printf("Press the button to receive SIGIO signals.\n");
    printf("Press Ctrl+C to exit.\n\n");

    /* 主循环 */
    while (1) {
        /* 等待信号 */
        pause();

        if (signal_received) {
            signal_received = 0;

            /* 读取按键状态 */
            ret = read(fd, &state, sizeof(state));
            if (ret == sizeof(state)) {
                printf("Button event: %s\n", state ? "PRESSED" : "RELEASED");
            } else if (ret < 0) {
                perror("read");
                break;
            }
        }
    }

    /* 清理 */
    close(fd);
    return 0;
}
```

## 替代方案：eventfd

除了传统的信号机制，Linux还提供了`eventfd`——一种更高效的异步通知机制。

### eventfd vs fasync

| 特性 | fasync (SIGIO) | eventfd |
| --- | --- | --- |
| 机制 | 信号 | 文件描述符 |
| 性能 | 较低 | 高 |
| 可扩展性 | 差 | 好 |
| 与poll/select集成 | 需要 | 原生支持 |

### eventfd的基本用法

```c
/* 创建eventfd */
int efd = eventfd(0, EFD_NONBLOCK);

/* 等待事件（poll/select/epoll） */
struct pollfd pfd = { .fd = efd, .events = POLLIN };
poll(&pfd, 1, -1);

/* 读取事件（清零计数器） */
uint64_t value;
read(efd, &value, sizeof(value));

/* 写入事件（通知） */
uint64_t value = 1;
write(efd, &value, sizeof(value));
```

## 关键点总结

1. **`fasync()`操作是必须的**，用于管理异步通知列表
2. **`kill_fasync()`发送信号**，在事件发生时调用
3. **应用程序需要设置`O_ASYNC`标志**和信号拥有者
4. **信号处理函数要尽量简单**，只做最少的处理
5. **读取操作要清除pending状态**，避免重复通知
6. **考虑用eventfd替代**，性能更好且更灵活

## 异步通知 vs 其他机制

| 机制 | 优点 | 缺点 | 适用场景 |
| --- | --- | --- | --- |
| 阻塞I/O | 简单 | 只能等一个FD | 单一数据源 |
| poll/select | 可监控多个FD | 需要轮询 | 多数据源 |
| 异步通知 | 主动通知 | 信号处理复杂 | 事件驱动 |
| eventfd | 高效，可组合 | 需要额外FD | 高性能场景 |

## 这一小节就到这里

异步通知是事件驱动编程的基础。虽然传统的SIGIO机制有一些限制，但它仍然是理解异步I/O的好方式。对于高性能应用，考虑使用eventfd或io_uring。

到这里，我们的内核核心功能教程就结束了。你已经掌握了：
* 并发控制（原子操作、自旋锁、互斥体）
* 时间管理（定时器）
* 中断处理
* I/O机制（阻塞、非阻塞、异步通知）

这些知识足以让你写出正确、高效的内核驱动了。

---

## 本章要点

1. **异步通知让驱动主动通知应用**，通过SIGIO信号。
2. **`fasync()`操作管理异步通知列表**，在应用设置FASYNC时调用。
3. **`kill_fasync()`发送信号**，在事件发生时调用。
4. **应用需设置`O_ASYNC`和信号拥有者**：`fcntl(fd, F_SETOWN, getpid())`。
5. **信号处理函数要简单**，复杂处理放在主循环。
6. **eventfd是更现代的替代方案**，性能更好且可组合。
