// SPDX-License-Identifier: GPL-2.0
/*
 * Spinlock Demo Driver
 *
 * This driver demonstrates the use of spinlocks in Linux kernel 7.0.
 * It shows the difference between protected and unprotected access to shared data.
 *
 * Environment: Linux 7.0-rc4, ARMv7-A (SMP)
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/sched/clock.h>
#include <linux/kthread.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>

static const char driver_name[] = "spinlock_demo";
static const char device_name[] = "spinlock_demo";

/* Device structure */
struct spinlock_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;

    /* Shared data */
    spinlock_t spin;
    int shared_counter;
    int unprotected_counter;

    /* Statistics */
    u64 protected_ops;
    u64 unprotected_ops;
    u64 spin_contentions;
    u64 max_hold_time_ns;

    /* Test control */
    bool test_running;
    struct task_struct *test_thread;
};

static struct spinlock_device *spinlock_devp;
static struct class *spinlock_class;

/* Simulate critical section operation */
static void do_critical_work(void)
{
    /* Simulate some work (non-sleeping) */
    udelay(1);
}

/* Protected increment using spinlock */
static int protected_increment(struct spinlock_device *dev)
{
    unsigned long flags;
    u64 start, end;
    int value;

    start = sched_clock();
    spin_lock_irqsave(&dev->spin, flags);

    dev->shared_counter++;
    value = dev->shared_counter;
    do_critical_work();

    end = sched_clock();
    if (end - start > dev->max_hold_time_ns)
        dev->max_hold_time_ns = end - start;

    spin_unlock_irqrestore(&dev->spin, flags);

    dev->protected_ops++;
    return value;
}

/* Unprotected increment (for comparison) */
static int unprotected_increment(struct spinlock_device *dev)
{
    int value;

    /* No lock - demonstrates race condition */
    dev->unprotected_counter++;
    value = dev->unprotected_counter;

    dev->unprotected_ops++;
    return value;
}

/* Device operations */
static int spinlock_open(struct inode *inode, struct file *file)
{
    struct spinlock_device *dev =
        container_of(inode->i_cdev, struct spinlock_device, cdev);

    file->private_data = dev;
    return 0;
}

static int spinlock_release(struct inode *inode, struct file *file)
{
    return 0;
}

static ssize_t spinlock_read(struct file *file,
                             char __user *buf,
                             size_t count,
                             loff_t *ppos)
{
    struct spinlock_device *dev = file->private_data;
    char kbuf[512];
    int len;

    mutex_lock(&dev->lock);

    len = snprintf(kbuf, sizeof(kbuf),
                   "Spinlock Demo Driver Statistics\n"
                   "==================================\n"
                   "Protected counter:   %d\n"
                   "Unprotected counter: %d\n"
                   "Protected ops:       %llu\n"
                   "Unprotected ops:     %llu\n"
                   "Max hold time:       %llu ns\n"
                   "\n"
                   "Commands (write):\n"
                   "  protected <n>   - Do n protected increments\n"
                   "  unprotected <n> - Do n unprotected increments\n"
                   "  reset           - Reset counters\n"
                   "  stress <n>      - Run stress test with n iterations\n",
                   dev->shared_counter,
                   dev->unprotected_counter,
                   dev->protected_ops,
                   dev->unprotected_ops,
                   dev->max_hold_time_ns);

    mutex_unlock(&dev->lock);

    if (*ppos >= len)
        return 0;

    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos = len;
    return len;
}

static ssize_t spinlock_write(struct file *file,
                              const char __user *buf,
                              size_t count,
                              loff_t *ppos)
{
    struct spinlock_device *dev = file->private_data;
    char kbuf[64];
    char op[32];
    int value = 0;
    int ret;
    int i;

    if (count >= sizeof(kbuf))
        return -EINVAL;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    ret = sscanf(kbuf, "%s %d", op, &value);
    if (ret < 1)
        return -EINVAL;

    mutex_lock(&dev->lock);

    if (strcmp(op, "protected") == 0) {
        int n = (ret >= 2) ? value : 1;
        for (i = 0; i < n; i++) {
            protected_increment(dev);
        }
        pr_info("spinlock_demo: performed %d protected increments\n", n);
    } else if (strcmp(op, "unprotected") == 0) {
        int n = (ret >= 2) ? value : 1;
        for (i = 0; i < n; i++) {
            unprotected_increment(dev);
        }
        pr_info("spinlock_demo: performed %d unprotected increments\n", n);
    } else if (strcmp(op, "reset") == 0) {
        dev->shared_counter = 0;
        dev->unprotected_counter = 0;
        dev->protected_ops = 0;
        dev->unprotected_ops = 0;
        dev->max_hold_time_ns = 0;
        pr_info("spinlock_demo: counters reset\n");
    } else if (strcmp(op, "stress") == 0) {
        int n = (ret >= 2) ? value : 1000;
        for (i = 0; i < n; i++) {
            protected_increment(dev);
            if (i % 100 == 0)
                cond_resched();
        }
        pr_info("spinlock_demo: stress test completed (%d iterations)\n", n);
    } else {
        mutex_unlock(&dev->lock);
        return -EINVAL;
    }

    mutex_unlock(&dev->lock);
    return count;
}

static const struct file_operations spinlock_fops = {
    .owner = THIS_MODULE,
    .open = spinlock_open,
    .release = spinlock_release,
    .read = spinlock_read,
    .write = spinlock_write,
};

/* Probe function */
static int spinlock_probe(struct platform_device *pdev)
{
    struct spinlock_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* Initialize spinlock */
    spin_lock_init(&dev->spin);
    mutex_init(&dev->lock);

    dev->shared_counter = 0;
    dev->unprotected_counter = 0;

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        pr_err("spinlock_demo: failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &spinlock_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("spinlock_demo: failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!spinlock_class) {
        spinlock_class = class_create(driver_name);
        if (IS_ERR(spinlock_class)) {
            ret = PTR_ERR(spinlock_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(spinlock_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    spinlock_devp = dev;

    pr_info("spinlock_demo: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(spinlock_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void spinlock_remove(struct platform_device *pdev)
{
    struct spinlock_device *dev = platform_get_drvdata(pdev);

    device_destroy(spinlock_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("spinlock_demo: device unregistered\n");
    pr_info("spinlock_demo: final counters: protected=%d, unprotected=%d\n",
            dev->shared_counter, dev->unprotected_counter);
}

/* Device tree match table */
static const struct of_device_id spinlock_match[] = {
    { .compatible = "imx,spinlock-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, spinlock_match);

/* Platform driver */
static struct platform_driver spinlock_driver = {
    .probe = spinlock_probe,
    .remove = spinlock_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = spinlock_match,
    },
};
module_platform_driver(spinlock_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Spinlock demo driver for Linux 7.0");
MODULE_VERSION("1.0");
