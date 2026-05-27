// SPDX-License-Identifier: GPL-2.0
/*
 * Interrupt Demo Driver
 *
 * This driver demonstrates interrupt handling in Linux 7.0.
 * Features:
 * - GPIO interrupt handling with work queue
 * - Button debounce handling
 * - Event notification to user space via wait queue
 * - Poll support for non-blocking access
 *
 * Environment: Linux 7.0-rc4, ARMv7-A
 */

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
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>

static const char driver_name[] = "interrupt_demo";
static const char device_name[] = "interrupt_demo";
static const int debounce_ms = 50;

/* Button event structure */
struct button_event {
    bool pressed;
    u64 timestamp_ns;
};

/* Device structure */
struct interrupt_device {
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

    /* Statistics */
    u64 press_count;
    u64 release_count;
    u64 irq_count;
    u64 debounce_skipped;
};

static struct interrupt_device *interrupt_devp;
static struct class *interrupt_class;

/* Work queue handler (process context, can sleep) */
static void interrupt_work_handler(struct work_struct *work)
{
    struct interrupt_device *dev =
        container_of(work, struct interrupt_device, work);
    bool state;
    unsigned long flags;
    ktime_t now;

    /* Debounce delay */
    msleep_interruptible(debounce_ms);

    /* Read stable state */
    state = gpiod_get_value(dev->gpio);
    now = ktime_get();

    spin_lock_irqsave(&dev->lock, flags);

    /* Only generate event on state change */
    if (state != dev->last_state) {
        dev->last_state = state;
        dev->event.pressed = state;
        dev->event.timestamp_ns = ktime_to_ns(now);
        dev->event_ready = true;

        if (state) {
            dev->press_count++;
            pr_info("interrupt_demo: Button PRESSED\n");
        } else {
            dev->release_count++;
            pr_info("interrupt_demo: Button RELEASED\n");
        }

        /* Wake up waiting readers */
        wake_up_interruptible(&dev->waitq);
    } else {
        dev->debounce_skipped++;
        pr_debug("interrupt_demo: Debounce skipped (state unchanged)\n");
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}

/* Hard interrupt handler (interrupt context, must be fast) */
static irqreturn_t interrupt_irq_handler(int irq, void *dev_id)
{
    struct interrupt_device *dev = dev_id;

    dev->irq_count++;

    /* Schedule work queue and return immediately */
    schedule_work(&dev->work);

    return IRQ_HANDLED;
}

/* Device operations: open */
static int interrupt_open(struct inode *inode, struct file *file)
{
    struct interrupt_device *dev =
        container_of(inode->i_cdev, struct interrupt_device, cdev);

    file->private_data = dev;
    pr_info("interrupt_demo: device opened\n");
    return 0;
}

/* Device operations: release */
static int interrupt_release(struct inode *inode, struct file *file)
{
    pr_info("interrupt_demo: device released\n");
    return 0;
}

/* Device operations: read button event */
static ssize_t interrupt_read(struct file *file,
                              char __user *buf,
                              size_t count,
                              loff_t *ppos)
{
    struct interrupt_device *dev = file->private_data;
    struct button_event event;
    unsigned long flags;
    int ret;

    /* Wait for event */
    ret = wait_event_interruptible(dev->waitq, dev->event_ready);
    if (ret)
        return -ERESTARTSYS;

    spin_lock_irqsave(&dev->lock, flags);

    /* Copy event */
    event = dev->event;
    dev->event_ready = false;

    spin_unlock_irqrestore(&dev->lock, flags);

    /* Return to user */
    if (copy_to_user(buf, &event, sizeof(event)))
        return -EFAULT;

    return sizeof(event);
}

/* Device operations: poll */
static __poll_t interrupt_poll(struct file *file,
                                poll_table *wait)
{
    struct interrupt_device *dev = file->private_data;
    __poll_t mask = 0;
    unsigned long flags;

    poll_wait(file, &dev->waitq, wait);

    spin_lock_irqsave(&dev->lock, flags);
    if (dev->event_ready)
        mask |= EPOLLIN | EPOLLRDNORM;
    spin_unlock_irqrestore(&dev->lock, flags);

    return mask;
}

/* Device operations: ioctl for statistics */
static long interrupt_ioctl(struct file *file,
                            unsigned int cmd, unsigned long arg)
{
    struct interrupt_device *dev = file->private_data;
    unsigned long flags;
    u64 stats[4];

    switch (cmd) {
    case 0:
        /* Get statistics */
        spin_lock_irqsave(&dev->lock, flags);
        stats[0] = dev->irq_count;
        stats[1] = dev->press_count;
        stats[2] = dev->release_count;
        stats[3] = dev->debounce_skipped;
        spin_unlock_irqrestore(&dev->lock, flags);

        if (copy_to_user((void __user *)arg, stats, sizeof(stats)))
            return -EFAULT;
        return 0;
    default:
        return -ENOTTY;
    }
}

static const struct file_operations interrupt_fops = {
    .owner = THIS_MODULE,
    .open = interrupt_open,
    .release = interrupt_release,
    .read = interrupt_read,
    .poll = interrupt_poll,
    .unlocked_ioctl = interrupt_ioctl,
    .llseek = noop_llseek,
};

/* Probe function */
static int interrupt_probe(struct platform_device *pdev)
{
    struct interrupt_device *dev;
    int ret;
    int irq_flags;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* Get GPIO */
    dev->gpio = devm_gpiod_get(&pdev->dev, "button", GPIOD_IN);
    if (IS_ERR(dev->gpio)) {
        ret = PTR_ERR(dev->gpio);
        dev_err(&pdev->dev, "failed to get GPIO: %d\n", ret);
        return ret;
    }

    /* Read initial state */
    dev->last_state = gpiod_get_value(dev->gpio);

    /* Get IRQ number */
    dev->irq = gpiod_to_irq(dev->gpio);
    if (dev->irq < 0) {
        dev_err(&pdev->dev, "failed to get IRQ\n");
        return dev->irq;
    }

    /* Initialize work queue */
    INIT_WORK(&dev->work, interrupt_work_handler);

    /* Initialize spinlock and wait queue */
    spin_lock_init(&dev->lock);
    init_waitqueue_head(&dev->waitq);

    /* Configure IRQ flags: both edges */
    irq_flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;
    irq_flags |= IRQF_SHARED;

    /* Register interrupt handler */
    ret = devm_request_irq(&pdev->dev, dev->irq,
                           interrupt_irq_handler,
                           irq_flags,
                           driver_name, dev);
    if (ret) {
        dev_err(&pdev->dev, "failed to request IRQ: %d\n", ret);
        return ret;
    }

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        dev_err(&pdev->dev, "failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &interrupt_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        dev_err(&pdev->dev, "failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!interrupt_class) {
        interrupt_class = class_create(driver_name);
        if (IS_ERR(interrupt_class)) {
            ret = PTR_ERR(interrupt_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(interrupt_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    interrupt_devp = dev;

    dev_info(&pdev->dev, "device registered (IRQ=%d)\n", dev->irq);
    return 0;

err_destroy_class:
    class_destroy(interrupt_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void interrupt_remove(struct platform_device *pdev)
{
    struct interrupt_device *dev = platform_get_drvdata(pdev);

    /* Cancel work queue */
    cancel_work_sync(&dev->work);

    device_destroy(interrupt_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "device unregistered\n");
    dev_info(&pdev->dev, "stats: irqs=%llu, presses=%llu, releases=%llu, skipped=%llu\n",
             dev->irq_count, dev->press_count, dev->release_count,
             dev->debounce_skipped);
}

/* Device tree match table */
static const struct of_device_id interrupt_match[] = {
    { .compatible = "imx,interrupt-demo" },
    { .compatible = "gpio-keys" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, interrupt_match);

/* Platform driver */
static struct platform_driver interrupt_driver = {
    .probe = interrupt_probe,
    .remove = interrupt_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = interrupt_match,
    },
};
module_platform_driver(interrupt_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Interrupt demo driver for Linux 7.0");
MODULE_VERSION("1.0");
