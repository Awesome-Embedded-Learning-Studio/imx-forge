// SPDX-License-Identifier: GPL-2.0
/*
 * Timer Demo Driver
 *
 * This driver demonstrates the use of kernel timers in Linux 7.0.
 * Uses the new timer_setup() API (not init_timer()).
 *
 * Environment: Linux 7.0-rc4, ARMv7-A
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/mutex.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>

static const char driver_name[] = "timer_demo";
static const char device_name[] = "timer_demo";
static const unsigned int default_interval_ms = 1000;

/* Device structure */
struct timer_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;
    struct timer_list timer;

    unsigned long interval_ms;
    u64 tick_count;
    bool running;

    /* Statistics */
    u64 total_ticks;
    u64 min_delta_ms;
    u64 max_delta_ms;
    u64 last_tick_time;
};

static struct timer_device *timer_devp;
static struct class *timer_class;

/* Timer callback function - Linux 7.0 style */
static void timer_callback(struct timer_list *timer)
{
    struct timer_device *dev = container_of(timer, struct timer_device, timer);
    u64 now = ktime_to_ms(ktime_get());
    u64 delta;

    dev->tick_count++;
    dev->total_ticks++;

    /* Calculate delta */
    if (dev->last_tick_time > 0) {
        delta = now - dev->last_tick_time;
        if (dev->total_ticks == 1) {
            dev->min_delta_ms = delta;
            dev->max_delta_ms = delta;
        } else {
            if (delta < dev->min_delta_ms)
                dev->min_delta_ms = delta;
            if (delta > dev->max_delta_ms)
                dev->max_delta_ms = delta;
        }
    }
    dev->last_tick_time = now;

    pr_info("timer_demo: tick %llu, delta=%llu ms\n",
            dev->tick_count, delta);

    /* Reschedule timer */
    if (dev->running) {
        mod_timer(&dev->timer,
                  jiffies + msecs_to_jiffies(dev->interval_ms));
    }
}

/* Device operations */
static int timer_open(struct inode *inode, struct file *file)
{
    struct timer_device *dev =
        container_of(inode->i_cdev, struct timer_device, cdev);

    file->private_data = dev;
    return 0;
}

static int timer_release(struct inode *inode, struct file *file)
{
    return 0;
}

static ssize_t timer_read(struct file *file,
                          char __user *buf,
                          size_t count,
                          loff_t *ppos)
{
    struct timer_device *dev = file->private_data;
    char kbuf[256];
    int len;
    u64 avg_delta = 0;

    mutex_lock(&dev->lock);

    if (dev->total_ticks > 1)
        avg_delta = (dev->max_delta_ms + dev->min_delta_ms) / 2;

    len = snprintf(kbuf, sizeof(kbuf),
                   "Timer Demo Driver\n"
                   "==================\n"
                   "Status: %s\n"
                   "Interval: %lu ms\n"
                   "Tick count: %llu\n"
                   "Total ticks: %llu\n"
                   "Min delta: %llu ms\n"
                   "Max delta: %llu ms\n"
                   "Avg delta: %llu ms\n"
                   "\n"
                   "Commands (write):\n"
                   "  start [ms]     - Start timer (optional interval in ms)\n"
                   "  stop           - Stop timer\n"
                   "  set <ms>        - Set interval (restarts if running)\n"
                   "  reset           - Reset statistics\n",
                   dev->running ? "running" : "stopped",
                   dev->interval_ms,
                   dev->tick_count,
                   dev->total_ticks,
                   dev->min_delta_ms,
                   dev->max_delta_ms,
                   avg_delta);

    mutex_unlock(&dev->lock);

    if (*ppos >= len)
        return 0;

    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos = len;
    return len;
}

static ssize_t timer_write(struct file *file,
                           const char __user *buf,
                           size_t count,
                           loff_t *ppos)
{
    struct timer_device *dev = file->private_data;
    char kbuf[64];
    char op[32];
    int value = 0;
    int ret;

    if (count >= sizeof(kbuf))
        return -EINVAL;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    ret = sscanf(kbuf, "%s %d", op, &value);
    if (ret < 1)
        return -EINVAL;

    mutex_lock(&dev->lock);

    if (strcmp(op, "start") == 0) {
        if (!dev->running) {
            dev->running = true;
            dev->tick_count = 0;
            dev->timer.expires = jiffies + msecs_to_jiffies(dev->interval_ms);
            add_timer(&dev->timer);
            pr_info("timer_demo: started with interval %lu ms\n",
                    dev->interval_ms);
        }
    } else if (strcmp(op, "stop") == 0) {
        if (dev->running) {
            dev->running = false;
            timer_delete_sync(&dev->timer);
            pr_info("timer_demo: stopped\n");
        }
    } else if (strcmp(op, "set") == 0) {
        if (ret >= 2 && value > 0) {
            bool was_running = dev->running;
            dev->interval_ms = value;
            if (was_running) {
                mod_timer(&dev->timer,
                          jiffies + msecs_to_jiffies(dev->interval_ms));
            }
            pr_info("timer_demo: interval set to %d ms\n", value);
        }
    } else if (strcmp(op, "reset") == 0) {
        dev->tick_count = 0;
        dev->total_ticks = 0;
        dev->min_delta_ms = 0;
        dev->max_delta_ms = 0;
        dev->last_tick_time = 0;
        pr_info("timer_demo: statistics reset\n");
    } else {
        mutex_unlock(&dev->lock);
        return -EINVAL;
    }

    mutex_unlock(&dev->lock);
    return count;
}

static const struct file_operations timer_fops = {
    .owner = THIS_MODULE,
    .open = timer_open,
    .release = timer_release,
    .read = timer_read,
    .write = timer_write,
};

/* Probe function */
static int timer_probe(struct platform_device *pdev)
{
    struct timer_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    mutex_init(&dev->lock);

    /* Initialize timer using Linux 7.0 API */
    dev->interval_ms = default_interval_ms;
    timer_setup(&dev->timer, timer_callback, 0);

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        pr_err("timer_demo: failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &timer_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("timer_demo: failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!timer_class) {
        timer_class = class_create(driver_name);
        if (IS_ERR(timer_class)) {
            ret = PTR_ERR(timer_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(timer_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    timer_devp = dev;

    pr_info("timer_demo: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(timer_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void timer_remove(struct platform_device *pdev)
{
    struct timer_device *dev = platform_get_drvdata(pdev);

    dev->running = false;
    timer_delete_sync(&dev->timer);

    device_destroy(timer_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("timer_demo: device unregistered\n");
}

/* Device tree match table */
static const struct of_device_id timer_match[] = {
    { .compatible = "imx,timer-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, timer_match);

/* Platform driver */
static struct platform_driver timer_driver = {
    .probe = timer_probe,
    .remove = timer_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = timer_match,
    },
};
module_platform_driver(timer_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Timer demo driver for Linux 7.0");
MODULE_VERSION("1.0");
