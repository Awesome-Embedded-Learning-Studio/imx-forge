// SPDX-License-Identifier: GPL-2.0
/*
 * Async Notification Demo Driver
 *
 * This driver demonstrates asynchronous notification in Linux 7.0.
 * Features:
 * - GPIO interrupt handling
 * - Async notification via SIGIO signal (fasync)
 * - Button state tracking
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
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/fcntl.h>
#include <linux/poll.h>
#include <linux/of.h>

static const char driver_name[] = "async_notify_demo";
static const char device_name[] = "async_notify_demo";

/* Device structure */
struct async_notify_device {
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
    wait_queue_head_t waitq;

    /* Statistics */
    u64 press_count;
    u64 release_count;
    u64 notify_count;
};

static struct async_notify_device *async_notify_devp;
static struct class *async_notify_class;

/* fasync operation */
static int async_notify_fasync(int fd, struct file *file, int on)
{
    struct async_notify_device *dev = file->private_data;

    return fasync_helper(fd, file, on, &dev->async_queue);
}

/* Send signal to user space */
static void send_signal(struct async_notify_device *dev)
{
    kill_fasync(&dev->async_queue, SIGIO, POLL_IN);

    dev->notify_count++;
    pr_info("async_notify_demo: signal sent (total: %llu)\n",
            dev->notify_count);
}

/* Interrupt handler */
static irqreturn_t async_notify_irq_handler(int irq, void *dev_id)
{
    struct async_notify_device *dev = dev_id;
    bool new_state;
    unsigned long flags;

    spin_lock_irqsave(&dev->lock, flags);

    /* Read button state */
    new_state = gpiod_get_value(dev->gpio);

    /* Only process on state change */
    if (new_state != dev->button_state) {
        dev->button_state = new_state;
        dev->event_pending = true;

        if (new_state) {
            dev->press_count++;
            pr_info("async_notify_demo: Button PRESSED\n");
        } else {
            dev->release_count++;
            pr_info("async_notify_demo: Button RELEASED\n");
        }

        /* Send async notification */
        send_signal(dev);
    }

    spin_unlock_irqrestore(&dev->lock, flags);

    return IRQ_HANDLED;
}

/* Device operation: open */
static int async_notify_open(struct inode *inode, struct file *file)
{
    struct async_notify_device *dev =
        container_of(inode->i_cdev, struct async_notify_device, cdev);

    file->private_data = dev;
    pr_info("async_notify_demo: device opened\n");
    return 0;
}

/* Device operation: release */
static int async_notify_release(struct inode *inode, struct file *file)
{
    /* Remove from async notification list */
    async_notify_fasync(-1, file, 0);

    pr_info("async_notify_demo: device released\n");
    return 0;
}

/* Device operation: read button state */
static ssize_t async_notify_read(struct file *file,
                                  char __user *buf,
                                  size_t count,
                                  loff_t *ppos)
{
    struct async_notify_device *dev = file->private_data;
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

/* Device operation: ioctl for statistics */
static long async_notify_ioctl(struct file *file,
                               unsigned int cmd, unsigned long arg)
{
    struct async_notify_device *dev = file->private_data;
    u64 stats[3];
    unsigned long flags;

    switch (cmd) {
    case 0:
        /* Get statistics */
        spin_lock_irqsave(&dev->lock, flags);
        stats[0] = dev->press_count;
        stats[1] = dev->release_count;
        stats[2] = dev->notify_count;
        spin_unlock_irqrestore(&dev->lock, flags);

        if (copy_to_user((void __user *)arg, stats, sizeof(stats)))
            return -EFAULT;
        return 0;
    default:
        return -ENOTTY;
    }
}

/* Poll operation */
static __poll_t async_notify_poll(struct file *file,
                                   poll_table *wait)
{
    struct async_notify_device *dev = file->private_data;
    __poll_t mask = 0;
    unsigned long flags;

    poll_wait(file, &dev->waitq, wait);

    spin_lock_irqsave(&dev->lock, flags);
    if (dev->event_pending)
        mask |= EPOLLIN | EPOLLRDNORM;
    spin_unlock_irqrestore(&dev->lock, flags);

    return mask;
}

static const struct file_operations async_notify_fops = {
    .owner = THIS_MODULE,
    .open = async_notify_open,
    .release = async_notify_release,
    .read = async_notify_read,
    .unlocked_ioctl = async_notify_ioctl,
    .poll = async_notify_poll,
    .fasync = async_notify_fasync,
};

/* Probe function */
static int async_notify_probe(struct platform_device *pdev)
{
    struct async_notify_device *dev;
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
    dev->button_state = gpiod_get_value(dev->gpio);

    /* Get IRQ number */
    dev->irq = gpiod_to_irq(dev->gpio);
    if (dev->irq < 0) {
        dev_err(&pdev->dev, "failed to get IRQ\n");
        return dev->irq;
    }

    /* Initialize spinlock and wait queue */
    spin_lock_init(&dev->lock);
    init_waitqueue_head(&dev->waitq);

    /* Configure IRQ flags: both edges */
    irq_flags = IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING;
    irq_flags |= IRQF_SHARED;

    /* Register interrupt handler */
    ret = devm_request_irq(&pdev->dev, dev->irq,
                           async_notify_irq_handler,
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
    cdev_init(&dev->cdev, &async_notify_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        dev_err(&pdev->dev, "failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!async_notify_class) {
        async_notify_class = class_create(driver_name);
        if (IS_ERR(async_notify_class)) {
            ret = PTR_ERR(async_notify_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(async_notify_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    async_notify_devp = dev;

    dev_info(&pdev->dev, "device registered (IRQ=%d)\n", dev->irq);
    return 0;

err_destroy_class:
    class_destroy(async_notify_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void async_notify_remove(struct platform_device *pdev)
{
    struct async_notify_device *dev = platform_get_drvdata(pdev);

    /* Send signal to wake up any waiting processes */
    kill_fasync(&dev->async_queue, SIGIO, POLL_HUP);

    device_destroy(async_notify_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "device unregistered\n");
    dev_info(&pdev->dev, "stats: presses=%llu, releases=%llu, notifies=%llu\n",
             dev->press_count, dev->release_count, dev->notify_count);
}

/* Device tree match table */
static const struct of_device_id async_notify_match[] = {
    { .compatible = "imx,async-notify-demo" },
    { .compatible = "gpio-keys" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, async_notify_match);

/* Platform driver */
static struct platform_driver async_notify_driver = {
    .probe = async_notify_probe,
    .remove = async_notify_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = async_notify_match,
    },
};
module_platform_driver(async_notify_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Async notification demo driver for Linux 7.0");
MODULE_VERSION("1.0");
