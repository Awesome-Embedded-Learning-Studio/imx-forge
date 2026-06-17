# 阻塞I/O实战指南：让进程正确睡觉的艺术

## 前言：为什么阻塞是高效的

在用户空间编程时，我们习惯了「非阻塞」的思维——调用函数立即返回，然后轮询结果。但在内核驱动开发中，**阻塞I/O反而是更高效的选择**。

为什么？

因为阻塞I/O让等待的进程进入睡眠，让出CPU给其他进程。当数据就绪时，内核再唤醒它。这样，CPU不会在轮询上浪费时间。

这一节，我们学习如何实现阻塞I/O，特别是**等待队列（Wait Queue）**——内核中实现阻塞的核心机制。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/wait.h` |

## 等待队列的基本概念

### 什么是等待队列？

等待队列是一个内核数据结构，用于管理等待某个条件成立的进程队列。

```
进程A [睡眠] ─┐
进程B [睡眠] ─┼──> 等待队列 ──> 条件变量
进程C [睡眠] ─┘
```

当条件成立时，内核会唤醒队列中的进程。

### 等待队列的结构

在Linux 7.0中，等待队列相关的类型是：

```c
/* 等待队列头 */
struct wait_queue_head {
    spinlock_t lock;
    struct list_head task_list;
};

typedef struct wait_queue_head wait_queue_head_t;

/* 等待队列项 */
struct wait_queue_entry {
    unsigned int flags;
    void *private;        /* 通常是当前进程 */
    wait_queue_func_t func;  /* 唤醒函数 */
    struct list_head entry;
};

typedef struct wait_queue_entry wait_queue_entry_t;
```

> **⚠️ 注意**：旧版内核使用`wait_queue_t`，Linux 4.x之后改名为`wait_queue_entry_t`。

## 初始化等待队列

### 静态初始化

```c
#include <linux/wait.h>

/* 定义并初始化等待队列头 */
static DECLARE_WAIT_QUEUE_HEAD(my_wq);
```

### 动态初始化

```c
static wait_queue_head_t my_wq;

/* 在初始化代码中 */
init_waitqueue_head(&my_wq);
```

## 等待事件：让进程睡觉

最常用的等待宏是`wait_event`系列：

### 基本等待

```c
/* 不可中断地等待条件成立 */
wait_event(wq, condition);

/* 可中断地等待（可被信号打断） */
wait_event_interruptible(wq, condition);

/* 带超时的等待 */
wait_event_timeout(wq, condition, timeout);
wait_event_interruptible_timeout(wq, condition, timeout);
```

### 参数说明

| 参数 | 描述 |
| --- | --- |
| `wq` | 等待队列头 |
| `condition` | 条件表达式（会被多次求值） |
| `timeout` | 超时时间（单位：jiffies） |

### 返回值

| 宏 | 返回值 |
| --- | --- |
| `wait_event()` | 无（永不返回，直到条件成立） |
| `wait_event_interruptible()` | `0`（条件成立），`-ERESTARTSYS`（被信号打断） |
| `wait_event_timeout()` | `0`（超时），`1`（条件成立） |
| `wait_event_interruptible_timeout()` | `0`（条件成立），`-ERESTARTSYS`（被信号打断），剩余jiffies（超时） |

## 唤醒等待：叫醒睡眠的进程

当条件可能成立时，需要唤醒等待的进程：

```c
/* 唤醒所有等待的进程 */
wake_up(&wq);

/* 只唤醒可中断的等待者 */
wake_up_interruptible(&wq);

/* 唤醒一个等待者（独占） */
wake_up_one(&wq);
```

## 完整示例：有界缓冲区驱动

让我们写一个模拟有界缓冲区的驱动，演示阻塞I/O的使用。

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/wait.h>
#include <linux/uaccess.h>

#define DRIVER_NAME "buffer_demo"
#define BUFFER_SIZE 16

struct buffer_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;
    wait_queue_head_t readq;
    wait_queue_head_t writeq;

    char buffer[BUFFER_SIZE];
    int head;
    int tail;
    int count;
};

static struct buffer_device *buffer_devp;
static struct class *buffer_class;

/* 检查缓冲区是否为空 */
static inline bool is_empty(struct buffer_device *dev)
{
    return dev->count == 0;
}

/* 检查缓冲区是否已满 */
static inline bool is_full(struct buffer_device *dev)
{
    return dev->count == BUFFER_SIZE;
}

/* 写入数据（生产者） */
static ssize_t buffer_write(struct file *file,
                            const char __user *buf,
                            size_t count,
                            loff_t *ppos)
{
    struct buffer_device *dev = file->private_data;
    ssize_t written = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    /* 写入循环 */
    while (written < count) {
        /* 等待缓冲区有空间 */
        wait_event_interruptible(dev->writeq, !is_full(dev));

        /* 检查是否被信号打断 */
        if (signal_pending(current)) {
            mutex_unlock(&dev->lock);
            return -ERESTARTSYS;
        }

        /* 写入一个字符 */
        if (copy_from_user(&ch, buf + written, 1)) {
            mutex_unlock(&dev->lock);
            return -EFAULT;
        }

        dev->buffer[dev->tail] = ch;
        dev->tail = (dev->tail + 1) % BUFFER_SIZE;
        dev->count++;
        written++;

        /* 唤醒读者 */
        wake_up_interruptible(&dev->readq);
    }

    mutex_unlock(&dev->lock);
    return written;
}

/* 读取数据（消费者） */
static ssize_t buffer_read(struct file *file,
                           char __user *buf,
                           size_t count,
                           loff_t *ppos)
{
    struct buffer_device *dev = file->private_data;
    ssize_t copied = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    /* 读取循环 */
    while (copied < count) {
        /* 等待缓冲区有数据 */
        wait_event_interruptible(dev->readq, !is_empty(dev));

        /* 检查是否被信号打断 */
        if (signal_pending(current)) {
            mutex_unlock(&dev->lock);
            return copied > 0 ? copied : -ERESTARTSYS;
        }

        /* 读取一个字符 */
        ch = dev->buffer[dev->head];
        dev->head = (dev->head + 1) % BUFFER_SIZE;
        dev->count--;

        if (copy_to_user(buf + copied, &ch, 1)) {
            mutex_unlock(&dev->lock);
            return -EFAULT;
        }

        copied++;

        /* 唤醒写者 */
        wake_up_interruptible(&dev->writeq);
    }

    mutex_unlock(&dev->lock);
    return copied;
}

/* 设备操作：打开 */
static int buffer_open(struct inode *inode, struct file *file)
{
    struct buffer_device *dev =
        container_of(inode->i_cdev, struct buffer_device, cdev);

    file->private_data = dev;
    return 0;
}

static const struct file_operations buffer_fops = {
    .owner = THIS_MODULE,
    .open = buffer_open,
    .read = buffer_read,
    .write = buffer_write,
};

/* Probe函数 */
static int buffer_probe(struct platform_device *pdev)
{
    struct buffer_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 初始化缓冲区 */
    dev->head = 0;
    dev->tail = 0;
    dev->count = 0;

    /* 初始化互斥体和等待队列 */
    mutex_init(&dev->lock);
    init_waitqueue_head(&dev->readq);
    init_waitqueue_head(&dev->writeq);

    /* 分配设备号 */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, DRIVER_NAME);
    if (ret) {
        pr_err("buffer: failed to allocate chrdev region\n");
        return ret;
    }

    /* 初始化字符设备 */
    cdev_init(&dev->cdev, &buffer_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("buffer: failed to add cdev\n");
        goto err_unregister;
    }

    /* 创建设备类 */
    if (!buffer_class) {
        buffer_class = class_create(DRIVER_NAME);
        if (IS_ERR(buffer_class)) {
            ret = PTR_ERR(buffer_class);
            goto err_del_cdev;
        }
    }

    /* 创建设备节点 */
    dev->device = device_create(buffer_class, &pdev->dev,
                                dev->dev_num, NULL,
                                DRIVER_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    buffer_devp = dev;

    pr_info("buffer: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(buffer_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove函数 */
static int buffer_remove(struct platform_device *pdev)
{
    struct buffer_device *dev = platform_get_drvdata(pdev);

    device_destroy(buffer_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("buffer: device unregistered\n");
    return 0;
}

static const struct of_device_id buffer_match[] = {
    { .compatible = "imx,buffer-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, buffer_match);

static struct platform_driver buffer_driver = {
    .probe = buffer_probe,
    .remove = buffer_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = buffer_match,
    },
};
module_platform_driver(buffer_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Blocking I/O demo driver");
```

## 用户态测试程序

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>

#define DEVICE "/dev/buffer_demo"

/* 生产者进程 */
void producer(int fd)
{
    const char *msg = "Hello, blocking I/O!";
    size_t len = strlen(msg);
    ssize_t ret;

    printf("Producer: writing %zu bytes\n", len);

    ret = write(fd, msg, len);
    if (ret < 0) {
        perror("write");
        return;
    }

    printf("Producer: wrote %zd bytes\n", ret);
}

/* 消费者进程 */
void consumer(int fd)
{
    char buf[128];
    ssize_t ret;

    printf("Consumer: waiting for data...\n");

    ret = read(fd, buf, sizeof(buf) - 1);
    if (ret < 0) {
        perror("read");
        return;
    }

    buf[ret] = '\0';
    printf("Consumer: read %zd bytes: %s\n", ret, buf);
}

int main(void)
{
    int fd;
    pid_t pid;

    fd = open(DEVICE, O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    pid = fork();
    if (pid < 0) {
        perror("fork");
        close(fd);
        return 1;
    }

    if (pid == 0) {
        /* 子进程：消费者 */
        sleep(1);  /* 让生产者先写 */
        consumer(fd);
    } else {
        /* 父进程：生产者 */
        producer(fd);
        wait(NULL);  /* 等待子进程 */
    }

    close(fd);
    return 0;
}
```

## 关键点解析

### 1. 为什么用两个等待队列？

我们使用`readq`和`writeq`两个等待队列：

* `readq`：读者等待数据
* `writeq`：写者等待空间

这样可以精确控制唤醒哪个队列，提高效率。

### 2. 条件检查的竞态

```c
while (copied < count) {
    wait_event_interruptible(dev->readq, !is_empty(dev));
    /* ... */
}
```

注意这里用`while`而不是`if`。因为`wait_event`宏在唤醒后会重新检查条件。如果有多个读者被唤醒，只有一个能读到数据，其他需要继续等待。

### 3. 信号处理

```c
if (signal_pending(current)) {
    mutex_unlock(&dev->lock);
    return -ERESTARTSYS;
}
```

`wait_event_interruptible`可能被信号打断（如用户按Ctrl+C）。我们需要检查并返回错误。

## 阻塞I/O vs 非阻塞I/O

| 特性 | 阻塞I/O | 非阻塞I/O |
| --- | --- | --- |
| CPU使用 | 低（进程睡眠） | 高（需要轮询） |
| 响应延迟 | 低（数据就绪立即唤醒） | 取决于轮询间隔 |
| 实现复杂度 | 中等 | 简单 |
| 适用场景 | 大多数情况 | 特殊需求 |

## 这一小节就到这里

阻塞I/O是内核驱动中最常用的模式。记住几个关键点：

1. **`wait_event_interruptible`可被信号打断**，必须检查返回值
2. **唤醒后要重新检查条件**，用`while`而不是`if`
3. **多个等待队列可以提高效率**，精确控制唤醒
4. **`wake_up`唤醒所有等待者**，`wake_up_one`只唤醒一个

下一节，我们学习非阻塞I/O和poll机制。

---

## 本章要点

1. **等待队列是实现阻塞I/O的核心**，`wait_queue_head_t`是队列头类型。
2. **`wait_event_interruptible`是最常用的等待宏**，可被信号打断。
3. **`wake_up_interruptible`唤醒等待者**，在条件可能成立时调用。
4. **条件检查要放在`while`循环中**，唤醒后重新检查。
5. **多个等待队列可以分离读者和写者**，提高效率。
6. **信号打断要返回`-ERESTARTSYS`**，用户空间会看到`EINTR`。
