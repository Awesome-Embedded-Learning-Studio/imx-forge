---
title: 非阻塞 I/O 与轮询
---

# 非阻塞I/O与轮询：从select到epoll的演进

## 前言：当阻塞不够用时

上一节我们讲了阻塞I/O，这是最常用的模式。但有些时候，阻塞I/O不够用：

* 应用程序需要同时监听多个文件描述符
* 应用程序不想被单个操作卡住
* 需要超时控制

这时候就需要**非阻塞I/O**和**轮询（poll）机制**。

在Linux中，有三套轮询API：
1. `select`：最老，有FD数量限制
2. `poll`：改进版，无FD数量限制
3. `epoll`：最新，性能最好（但驱动实现相同）

这一节，我们学习如何在驱动中实现poll支持。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/poll.h` |

## 非阻塞I/O的基本概念

### 阻塞 vs 非阻塞

```c
/* 阻塞模式（默认） */
int fd = open("/dev/mydevice", O_RDWR);
count = read(fd, buf, size);  /* 等待数据... */

/* 非阻塞模式 */
int fd = open("/dev/mydevice", O_RDWR | O_NONBLOCK);
count = read(fd, buf, size);  /* 立即返回 */
if (count < 0 && errno == EAGAIN) {
    /* 没有数据，稍后重试 */
}
```

### O_NONBLOCK标志

`O_NONBLOCK`标志让I/O操作立即返回：
* 如果操作可以立即完成，返回成功
* 如果不能，返回`-EAGAIN`

## 驱动中的poll实现

### poll操作

驱动需要实现`poll`文件操作：

```c
unsigned int (*poll)(struct file *file,
                     struct poll_table_struct *wait);
```

### poll实现模板

```c
static unsigned int my_poll(struct file *file,
                            poll_table *wait)
{
    struct my_device *dev = file->private_data;
    unsigned int mask = 0;

    /* 1. 注册等待队列 */
    poll_wait(file, &dev->waitq, wait);

    /* 2. 检查状态并返回事件掩码 */
    if (data_available(dev))
        mask |= EPOLLIN | EPOLLRDNORM;  /* 可读 */
    if (space_available(dev))
        mask |= EPOLLOUT | EPOLLWRNORM;  /* 可写 */
    if (error_pending(dev))
        mask |= EPOLLERR;  /* 错误 */

    return mask;
}
```

### poll_wait的作用

`poll_wait()`不会等待，它只是把等待队列注册到poll表中。内核会在适当的时候唤醒这些等待队列。

### 事件掩码

| 事件 | 描述 |
| --- | --- |
| `EPOLLIN` | 可读（普通数据） |
| `EPOLLRDNORM` | 可读（普通优先级） |
| `EPOLLPRI` | 可读（高优先级/带外数据） |
| `EPOLLOUT` | 可写 |
| `EPOLLWRNORM` | 可写（普通优先级） |
| `EPOLLERR` | 错误状态 |
| `EPOLLHUP` | 挂起状态 |
| `EPOLLPRI` | 紧急数据 |
| `EPOLLNVAL` | 无效请求 |

## 完整示例：支持poll的字符设备

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
#include <linux/poll.h>
#include <linux/uaccess.h>

#define DRIVER_NAME "poll_demo"
#define BUFFER_SIZE 64

struct poll_device {
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

static struct poll_device *poll_devp;
static struct class *poll_class;

static inline bool is_empty(struct poll_device *dev)
{
    return dev->count == 0;
}

static inline bool is_full(struct poll_device *dev)
{
    return dev->count == BUFFER_SIZE;
}

static inline int space_avail(struct poll_device *dev)
{
    return BUFFER_SIZE - dev->count;
}

/* poll操作 */
static unsigned int poll_poll(struct file *file,
                              poll_table *wait)
{
    struct poll_device *dev = file->private_data;
    unsigned int mask = 0;

    mutex_lock(&dev->lock);

    /* 注册等待队列 */
    poll_wait(file, &dev->readq, wait);
    poll_wait(file, &dev->writeq, wait);

    /* 检查可读状态 */
    if (!is_empty(dev))
        mask |= EPOLLIN | EPOLLRDNORM;

    /* 检查可写状态 */
    if (!is_full(dev))
        mask |= EPOLLOUT | EPOLLWRNORM;

    mutex_unlock(&dev->lock);

    return mask;
}

/* 写入数据 */
static ssize_t poll_write(struct file *file,
                          const char __user *buf,
                          size_t count,
                          loff_t *ppos)
{
    struct poll_device *dev = file->private_data;
    ssize_t written = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    while (written < count) {
        /* 非阻塞检查 */
        if (file->f_flags & O_NONBLOCK && is_full(dev)) {
            if (written == 0) {
                written = -EAGAIN;
            }
            break;
        }

        /* 等待空间 */
        if (wait_event_interruptible(dev->writeq,
                                      !is_full(dev))) {
            if (written == 0)
                written = -ERESTARTSYS;
            break;
        }

        /* 写入字符 */
        if (copy_from_user(&ch, buf + written, 1)) {
            written = -EFAULT;
            break;
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

/* 读取数据 */
static ssize_t poll_read(struct file *file,
                         char __user *buf,
                         size_t count,
                         loff_t *ppos)
{
    struct poll_device *dev = file->private_data;
    ssize_t copied = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    while (copied < count) {
        /* 非阻塞检查 */
        if (file->f_flags & O_NONBLOCK && is_empty(dev)) {
            if (copied == 0) {
                copied = -EAGAIN;
            }
            break;
        }

        /* 等待数据 */
        if (wait_event_interruptible(dev->readq,
                                      !is_empty(dev))) {
            if (copied == 0)
                copied = -ERESTARTSYS;
            break;
        }

        /* 读取字符 */
        ch = dev->buffer[dev->head];
        dev->head = (dev->head + 1) % BUFFER_SIZE;
        dev->count--;

        if (copy_to_user(buf + copied, &ch, 1)) {
            copied = -EFAULT;
            break;
        }

        copied++;

        /* 唤醒写者 */
        wake_up_interruptible(&dev->writeq);
    }

    mutex_unlock(&dev->lock);
    return copied;
}

/* 设备操作：打开 */
static int poll_open(struct inode *inode, struct file *file)
{
    struct poll_device *dev =
        container_of(inode->i_cdev, struct poll_device, cdev);

    file->private_data = dev;

    /* 打印模式 */
    if (file->f_flags & O_NONBLOCK)
        pr_info("poll: opened in non-blocking mode\n");
    else
        pr_info("poll: opened in blocking mode\n");

    return 0;
}

static const struct file_operations poll_fops = {
    .owner = THIS_MODULE,
    .open = poll_open,
    .read = poll_read,
    .write = poll_write,
    .poll = poll_poll,
};

/* Probe函数 */
static int poll_probe(struct platform_device *pdev)
{
    struct poll_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    dev->head = 0;
    dev->tail = 0;
    dev->count = 0;

    mutex_init(&dev->lock);
    init_waitqueue_head(&dev->readq);
    init_waitqueue_head(&dev->writeq);

    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, DRIVER_NAME);
    if (ret) {
        pr_err("poll: failed to allocate chrdev region\n");
        return ret;
    }

    cdev_init(&dev->cdev, &poll_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("poll: failed to add cdev\n");
        goto err_unregister;
    }

    if (!poll_class) {
        poll_class = class_create(DRIVER_NAME);
        if (IS_ERR(poll_class)) {
            ret = PTR_ERR(poll_class);
            goto err_del_cdev;
        }
    }

    dev->device = device_create(poll_class, &pdev->dev,
                                dev->dev_num, NULL,
                                DRIVER_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    poll_devp = dev;

    pr_info("poll: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(poll_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove函数 */
static int poll_remove(struct platform_device *pdev)
{
    struct poll_device *dev = platform_get_drvdata(pdev);

    device_destroy(poll_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("poll: device unregistered\n");
    return 0;
}

static const struct of_device_id poll_match[] = {
    { .compatible = "imx,poll-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, poll_match);

static struct platform_driver poll_driver = {
    .probe = poll_probe,
    .remove = poll_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = poll_match,
    },
};
module_platform_driver(poll_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Poll/Non-blocking I/O demo driver");
```

## 用户态测试程序

### 使用select

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/select.h>
#include <errno.h>

#define DEVICE "/dev/poll_demo"

int main(void)
{
    int fd;
    fd_set readfds;
    struct timeval timeout;
    char buf[128];
    ssize_t ret;

    fd = open(DEVICE, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Using select() to poll device...\n");

    while (1) {
        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);

        /* 2秒超时 */
        timeout.tv_sec = 2;
        timeout.tv_usec = 0;

        /* 等待设备可读 */
        ret = select(fd + 1, &readfds, NULL, NULL, &timeout);

        if (ret < 0) {
            perror("select");
            break;
        } else if (ret == 0) {
            printf("Timeout: no data within 2 seconds\n");
            continue;
        }

        if (FD_ISSET(fd, &readfds)) {
            ret = read(fd, buf, sizeof(buf) - 1);
            if (ret > 0) {
                buf[ret] = '\0';
                printf("Read %zd bytes: %s\n", ret, buf);
            } else if (ret < 0 && errno != EAGAIN) {
                perror("read");
                break;
            }
        }
    }

    close(fd);
    return 0;
}
```

### 使用poll

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>

#define DEVICE "/dev/poll_demo"

int main(void)
{
    int fd;
    struct pollfd pfd;
    char buf[128];
    ssize_t ret;

    fd = open(DEVICE, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Using poll() to poll device...\n");

    pfd.fd = fd;
    pfd.events = POLLIN;  /* 等待可读 */

    while (1) {
        /* 2秒超时 */
        ret = poll(&pfd, 1, 2000);

        if (ret < 0) {
            perror("poll");
            break;
        } else if (ret == 0) {
            printf("Timeout: no data within 2 seconds\n");
            continue;
        }

        if (pfd.revents & POLLIN) {
            ret = read(fd, buf, sizeof(buf) - 1);
            if (ret > 0) {
                buf[ret] = '\0';
                printf("Read %zd bytes: %s\n", ret, buf);
            } else if (ret < 0 && errno != EAGAIN) {
                perror("read");
                break;
            }
        }
    }

    close(fd);
    return 0;
}
```

### 使用epoll（最佳性能）

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/epoll.h>
#include <errno.h>

#define DEVICE "/dev/poll_demo"
#define MAX_EVENTS 1

int main(void)
{
    int fd, epfd;
    struct epoll_event ev, events[MAX_EVENTS];
    char buf[128];
    ssize_t ret;
    int nfds;

    fd = open(DEVICE, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    /* 创建epoll实例 */
    epfd = epoll_create1(0);
    if (epfd < 0) {
        perror("epoll_create1");
        close(fd);
        return 1;
    }

    /* 添加文件描述符到epoll */
    ev.events = EPOLLIN;
    ev.data.fd = fd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) < 0) {
        perror("epoll_ctl");
        close(epfd);
        close(fd);
        return 1;
    }

    printf("Using epoll() to poll device...\n");

    while (1) {
        /* 等待事件，2秒超时 */
        nfds = epoll_wait(epfd, events, MAX_EVENTS, 2000);

        if (nfds < 0) {
            perror("epoll_wait");
            break;
        } else if (nfds == 0) {
            printf("Timeout: no data within 2 seconds\n");
            continue;
        }

        for (int i = 0; i < nfds; i++) {
            if (events[i].events & EPOLLIN) {
                ret = read(events[i].data.fd, buf, sizeof(buf) - 1);
                if (ret > 0) {
                    buf[ret] = '\0';
                    printf("Read %zd bytes: %s\n", ret, buf);
                } else if (ret < 0 && errno != EAGAIN) {
                    perror("read");
                    goto out;
                }
            }
        }
    }

out:
    close(epfd);
    close(fd);
    return 0;
}
```

## select vs poll vs epoll

| 特性 | select | poll | epoll |
| --- | --- | --- | --- |
| FD数量限制 | 1024（可修改） | 无限制 | 无限制 |
| 性能（FD多时） | O(n) | O(n) | O(1) |
| 跨平台 | 是 | 是 | 仅Linux |
| 复杂度 | 简单 | 简单 | 较复杂 |
| 适用场景 | FD少 | FD中等 | FD很多 |

## 关键点总结

1. **`poll_wait()`不等待**，只是注册等待队列
2. **`O_NONBLOCK`标志控制非阻塞行为**
3. **事件掩码要正确设置**：`EPOLLIN`/`EPOLLOUT`
4. **唤醒后要检查实际状态**，可能多个进程被唤醒
5. **select/poll/epoll在驱动侧实现相同**，只是用户态API不同

## 这一小节就到这里

非阻塞I/O和poll机制让应用程序可以同时处理多个文件描述符，而不需要多线程或多进程。这是高性能网络编程的基础。

下一节，我们学习异步通知——让硬件主动「找」你的机制。

---

## 本章要点

1. **`O_NONBLOCK`标志启用非阻塞模式**，操作立即返回。
2. **`poll()`操作返回事件掩码**，告诉用户空间可以做什么。
3. **`poll_wait()`注册等待队列**，不实际等待。
4. **`EPOLLIN`/`EPOLLOUT`是最常用的事件**。
5. **select/poll/epoll是用户态API**，驱动侧实现相同。
6. **非阻塞操作返回`-EAGAIN`**，用户空间检查`errno`。
