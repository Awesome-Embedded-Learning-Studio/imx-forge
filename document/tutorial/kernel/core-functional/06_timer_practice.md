---
title: 定时器实战
---

# Linux 7.0内核定时器实战指南：从timer_setup到完整驱动

## 前言：为什么你需要实战

上一节我们讲了时间管理的理论。老实说，光是看API文档，你可能觉得自己懂了。但真正写代码的时候，你会发现一堆坑等着你。

比如：
* `timer_setup()`的回调函数签名是什么？
* 怎么从回调函数拿到我的设备结构体？
* 定时器删除时为什么要用`timer_delete_sync()`？
* 周期性定时器怎么实现？

这一节，我们写一个完整的定时器驱动，把这些都串起来。

## 环境：基于Linux 7.1

| 项目 | 版本/信息 |
|------|-----------|
| 内核版本 | Linux 7.1 (主线内核) |
| 架构 | ARMv7-A (Cortex-A7) |
| 相关头文件 | `include/linux/timer.h` |

## 定时器回调函数的正确签名

在Linux 7.0中，定时器回调函数的签名是固定的：

```c
void callback(struct timer_list *timer);
```

**⚠️ 重要**：回调函数只有一个参数——`timer_list`指针，没有`unsigned long data`了。

### 如何获取设备结构体？

新的API使用`from_timer()`宏来获取包含定时器的结构体：

```c
struct my_device {
    struct timer_list timer;
    int data;
    /* ... */
};

void my_callback(struct timer_list *timer)
{
    /* 从timer指针获取包含它的my_device结构体 */
    struct my_device *dev = from_timer(dev, timer, timer);

    /* 现在可以访问dev->data了 */
    pr_info("data = %d\n", dev->data);
}
```

`from_timer()`的本质是`container_of()`，它根据结构体成员的指针反推结构体本身的地址。

## 完整示例：带统计功能的定时器驱动

让我们写一个完整的字符设备驱动，它：
1. 定期产生统计数据
2. 用户可以读取统计信息
3. 支持配置采样间隔

```c
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/slab.h>

#define DRIVER_NAME "timer_demo"
#define DEFAULT_INTERVAL_MS 1000

struct timer_demo_dev {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;
    struct timer_list timer;

    unsigned long interval_ms;
    u64 sample_count;
    u64 last_jiffies;

    /* 统计数据 */
    u64 min_delta;
    u64 max_delta;
    u64 total_delta;
};

static struct timer_demo_dev *demo_dev;
static struct class *timer_demo_class;

/* 定时器回调函数 */
static void timer_demo_callback(struct timer_list *timer)
{
    struct timer_demo_dev *dev = from_timer(dev, timer, timer);
    unsigned long now = jiffies;
    u64 delta;

    /* 计算时间差 */
    delta = jiffies_to_msecs(now - dev->last_jiffies);
    dev->last_jiffies = now;

    /* 更新统计 */
    dev->sample_count++;
    dev->total_delta += delta;

    if (dev->sample_count == 1) {
        dev->min_delta = delta;
        dev->max_delta = delta;
    } else {
        if (delta < dev->min_delta)
            dev->min_delta = delta;
        if (delta > dev->max_delta)
            dev->max_delta = delta;
    }

    /* 打印日志 */
    pr_info("timer_demo: sample %llu, delta=%llu ms\n",
            dev->sample_count, delta);

    /* 重新设置定时器 */
    mod_timer(&dev->timer,
              now + msecs_to_jiffies(dev->interval_ms));
}

/* 设备操作：打开 */
static int timer_demo_open(struct inode *inode, struct file *file)
{
    struct timer_demo_dev *dev =
        container_of(inode->i_cdev, struct timer_demo_dev, cdev);

    file->private_data = dev;
    pr_info("timer_demo: device opened\n");
    return 0;
}

/* 设备操作：读取统计信息 */
static ssize_t timer_demo_read(struct file *file,
                               char __user *buf,
                               size_t count,
                               loff_t *ppos)
{
    struct timer_demo_dev *dev = file->private_data;
    char kbuf[256];
    int len;
    u64 avg_delta;

    mutex_lock(&dev->lock);

    if (dev->sample_count == 0) {
        avg_delta = 0;
    } else {
        avg_delta = dev->total_delta / dev->sample_count;
    }

    len = snprintf(kbuf, sizeof(kbuf),
                   "Samples: %llu\n"
                   "Min delta: %llu ms\n"
                   "Max delta: %llu ms\n"
                   "Avg delta: %llu ms\n"
                   "Interval: %lu ms\n",
                   dev->sample_count,
                   dev->min_delta,
                   dev->max_delta,
                   avg_delta,
                   dev->interval_ms);

    mutex_unlock(&dev->lock);

    if (*ppos >= len)
        return 0;  /* EOF */

    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos = len;
    return len;
}

/* 设备操作：写入配置 */
static ssize_t timer_demo_write(struct file *file,
                                const char __user *buf,
                                size_t count,
                                loff_t *ppos)
{
    struct timer_demo_dev *dev = file->private_data;
    unsigned long val;
    char kbuf[32];
    int ret;

    if (count >= sizeof(kbuf))
        return -EINVAL;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    ret = kstrtoul(kbuf, 10, &val);
    if (ret)
        return -EINVAL;

    if (val < 10 || val > 60000)
        return -EINVAL;

    mutex_lock(&dev->lock);

    dev->interval_ms = val;

    /* 重置统计 */
    dev->sample_count = 0;
    dev->total_delta = 0;
    dev->min_delta = 0;
    dev->max_delta = 0;

    /* 重新启动定时器 */
    mod_timer(&dev->timer,
              jiffies + msecs_to_jiffies(dev->interval_ms));

    mutex_unlock(&dev->lock);

    pr_info("timer_demo: interval set to %lu ms\n", val);
    return count;
}

static const struct file_operations timer_demo_fops = {
    .owner = THIS_MODULE,
    .open = timer_demo_open,
    .read = timer_demo_read,
    .write = timer_demo_write,
};

/* Probe函数 */
static int timer_demo_probe(struct platform_device *pdev)
{
    struct timer_demo_dev *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* 初始化互斥体 */
    mutex_init(&dev->lock);

    /* 初始化定时器 */
    dev->interval_ms = DEFAULT_INTERVAL_MS;
    dev->sample_count = 0;
    dev->last_jiffies = jiffies;
    timer_setup(&dev->timer, timer_demo_callback, 0);

    /* 分配设备号 */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, DRIVER_NAME);
    if (ret) {
        pr_err("timer_demo: failed to allocate chrdev region\n");
        return ret;
    }

    /* 初始化字符设备 */
    cdev_init(&dev->cdev, &timer_demo_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("timer_demo: failed to add cdev\n");
        goto err_unregister;
    }

    /* 创建设备类 */
    if (!timer_demo_class) {
        timer_demo_class = class_create(DRIVER_NAME);
        if (IS_ERR(timer_demo_class)) {
            ret = PTR_ERR(timer_demo_class);
            goto err_del_cdev;
        }
    }

    /* 创建设备节点 */
    dev->device = device_create(timer_demo_class, &pdev->dev,
                                dev->dev_num, NULL,
                                DRIVER_NAME);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    demo_dev = dev;

    /* 启动定时器 */
    dev->timer.expires = jiffies + msecs_to_jiffies(dev->interval_ms);
    add_timer(&dev->timer);

    pr_info("timer_demo: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(timer_demo_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove函数 */
static int timer_demo_remove(struct platform_device *pdev)
{
    struct timer_demo_dev *dev = platform_get_drvdata(pdev);

    /* 删除定时器并等待回调完成 */
    timer_delete_sync(&dev->timer);

    device_destroy(timer_demo_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("timer_demo: device unregistered\n");
    return 0;
}

static const struct of_device_id timer_demo_match[] = {
    { .compatible = "imx,timer-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, timer_demo_match);

static struct platform_driver timer_demo_driver = {
    .probe = timer_demo_probe,
    .remove = timer_demo_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = timer_demo_match,
    },
};
module_platform_driver(timer_demo_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Timer demo driver for Linux 7.0");
```

## 关键点解析

### 1. 为什么用`timer_delete_sync()`？

```c
timer_delete_sync(&dev->timer);
```

这个函数不仅删除定时器，还会**确保当前正在运行的回调函数完成**。

如果你用的是`timer_delete()`（或旧的`del_timer()`），定时器被删除后，回调函数可能还在另一个CPU上运行。这时候释放设备结构体会导致UAF（Use-After-Free）漏洞。

**⚠️ 规则**：

> 在释放包含定时器的结构体之前，**必须**使用`timer_delete_sync()`。

### 2. 为什么在回调中重新设置定时器？

```c
mod_timer(&dev->timer,
          now + msecs_to_jiffies(dev->interval_ms));
```

这是实现周期性定时器的方式。`mod_timer()`会：
* 如果定时器未激活，激活它
* 如果定时器已激活，更新其过期时间

### 3. 为什么需要互斥体？

定时器回调可能在一个CPU上运行，而`read()`/`write()`在另一个CPU上运行。它们可能同时访问`dev->sample_count`等变量，需要互斥体保护。

## 常见错误与调试

### 错误1：回调函数签名错误

```c
/* ❌ 错误：旧式签名 */
void callback(unsigned long data)
{
    /* ... */
}

/* ✓ 正确：新式签名 */
void callback(struct timer_list *timer)
{
    /* ... */
}
```

### 错误2：忘记使用`from_timer()`

```c
/* ❌ 错误：没有data字段了 */
void callback(struct timer_list *timer)
{
    struct my_device *dev = (struct my_device *)timer->data;
    /* 编译错误！ */
}

/* ✓ 正确：使用from_timer */
void callback(struct timer_list *timer)
{
    struct my_device *dev = from_timer(dev, timer, timer);
    /* ... */
}
```

### 错误3：定时器回调中睡眠

```c
/* ❌ 错误：定时器回调中不能睡眠 */
static void timer_callback(struct timer_list *timer)
{
    /* 定时器回调在软中断上下文，不能睡眠！ */
    msleep(100);  /* 死机！ */
}

/* ✓ 正确：使用忙等待或重新调度定时器 */
static void timer_callback(struct timer_list *timer)
{
    /* 如果需要延迟，重新设置定时器 */
    mod_timer(timer, jiffies + msecs_to_jiffies(100));
}
```

### 调试技巧

启用内核定时器调试选项：

```
CONFIG_DEBUG_OBJECTS_TIMERS=y
CONFIG_TIMER_STATS=y
```

然后可以用`cr工具`查看定时器统计：

```bash
$ cat /proc/timer_list
```

## 测试程序

用户态测试程序：

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#define DEVICE "/dev/timer_demo"

int main(void)
{
    int fd;
    char buf[256];
    ssize_t ret;

    fd = open(DEVICE, O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    /* 读取统计信息 */
    sleep(3);
    lseek(fd, 0, SEEK_SET);
    ret = read(fd, buf, sizeof(buf) - 1);
    if (ret > 0) {
        buf[ret] = '\0';
        printf("Statistics:\n%s\n", buf);
    }

    /* 修改采样间隔为500ms */
    write(fd, "500", 4);

    printf("Interval set to 500ms\n");
    sleep(3);

    /* 再次读取 */
    lseek(fd, 0, SEEK_SET);
    ret = read(fd, buf, sizeof(buf) - 1);
    if (ret > 0) {
        buf[ret] = '\0';
        printf("Statistics:\n%s\n", buf);
    }

    close(fd);
    return 0;
}
```

## 这一小节就到这里

Linux 7.0的定时器API虽然比旧版简洁，但需要正确使用`timer_setup()`和`from_timer()`。记住几个关键点：

1. **回调签名是固定的**：`void callback(struct timer_list *timer)`
2. **用`from_timer()`获取设备结构体**
3. **清理时用`timer_delete_sync()`**
4. **回调中不能睡眠**，需要延迟时重新设置定时器

下一节，我们进入中断的世界——那是另一种让内核「跳起来」的机制。

---

## 本章要点

1. **Linux 7.0使用新的timer API**：`timer_setup()`替代`init_timer()`，`from_timer()`替代`data`。
2. **回调函数签名固定**：`void callback(struct timer_list *timer)`。
3. **`timer_delete_sync()`确保安全**：等待回调完成后才返回，防止UAF。
4. **周期性定时器用`mod_timer()`**：在回调中重新设置过期时间。
5. **定时器回调不能睡眠**：在软中断上下文执行，只能用忙等待或重新调度。
6. **多CPU访问需要互斥体**：保护定时器数据和设备结构体。
