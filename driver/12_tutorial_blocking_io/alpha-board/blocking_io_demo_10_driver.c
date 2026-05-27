// SPDX-License-Identifier: GPL-2.0
/*
 * Blocking I/O Demo Driver
 *
 * This driver demonstrates blocking I/O operations in Linux 7.0.
 * Features:
 * - Bounded buffer implementation (producer-consumer)
 * - Wait queues for reader and writer
 * - Blocking read/write operations
 *
 * Environment: Linux 7.0-rc4, ARMv7-A
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/wait.h>
#include <linux/uaccess.h>
#include <linux/sched/signal.h>
#include <linux/of.h>

static const char driver_name[] = "blocking_io_demo";
static const char device_name[] = "blocking_io_demo";
static const int buffer_size = 16;

/* Device structure */
struct blocking_io_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;
    wait_queue_head_t readq;
    wait_queue_head_t writeq;

    char buffer[16];
    int head;
    int tail;
    int count;

    /* Statistics */
    u64 total_reads;
    u64 total_writes;
    u64 read_blocks;
    u64 write_blocks;
};

static struct blocking_io_device *blocking_io_devp;
static struct class *blocking_io_class;

/* Check if buffer is empty */
static inline bool is_empty(struct blocking_io_device *dev)
{
    return dev->count == 0;
}

/* Check if buffer is full */
static inline bool is_full(struct blocking_io_device *dev)
{
    return dev->count == buffer_size;
}

/* Device operations: open */
static int blocking_io_open(struct inode *inode, struct file *file)
{
    struct blocking_io_device *dev =
        container_of(inode->i_cdev, struct blocking_io_device, cdev);

    file->private_data = dev;
    pr_info("blocking_io_demo: device opened\n");
    return 0;
}

/* Device operations: release */
static int blocking_io_release(struct inode *inode, struct file *file)
{
    pr_info("blocking_io_demo: device released\n");
    return 0;
}

/* Write data (producer) */
static ssize_t blocking_io_write(struct file *file,
                                 const char __user *buf,
                                 size_t count,
                                 loff_t *ppos)
{
    struct blocking_io_device *dev = file->private_data;
    ssize_t written = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    /* Write loop */
    while (written < count) {
        /* Wait for buffer space */
        while (is_full(dev)) {
            dev->write_blocks++;
            mutex_unlock(&dev->lock);

            /* Wait for space to become available */
            if (wait_event_interruptible(dev->writeq, !is_full(dev))) {
                /* Check if we already wrote something */
                if (written > 0)
                    return written;
                return -ERESTARTSYS;
            }

            mutex_lock(&dev->lock);
        }

        /* Write a character */
        if (copy_from_user(&ch, buf + written, 1)) {
            mutex_unlock(&dev->lock);
            return -EFAULT;
        }

        dev->buffer[dev->tail] = ch;
        dev->tail = (dev->tail + 1) % buffer_size;
        dev->count++;
        written++;

        /* Wake up readers */
        wake_up_interruptible(&dev->readq);
    }

    dev->total_writes += written;
    mutex_unlock(&dev->lock);

    pr_info("blocking_io_demo: wrote %zd bytes\n", written);
    return written;
}

/* Read data (consumer) */
static ssize_t blocking_io_read(struct file *file,
                                char __user *buf,
                                size_t count,
                                loff_t *ppos)
{
    struct blocking_io_device *dev = file->private_data;
    ssize_t copied = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    /* Read loop */
    while (copied < count) {
        /* Wait for data */
        while (is_empty(dev)) {
            dev->read_blocks++;
            mutex_unlock(&dev->lock);

            /* Wait for data to become available */
            if (wait_event_interruptible(dev->readq, !is_empty(dev))) {
                /* Check if we already read something */
                if (copied > 0)
                    return copied;
                return -ERESTARTSYS;
            }

            mutex_lock(&dev->lock);
        }

        /* Read a character */
        ch = dev->buffer[dev->head];
        dev->head = (dev->head + 1) % buffer_size;
        dev->count--;

        if (copy_to_user(buf + copied, &ch, 1)) {
            mutex_unlock(&dev->lock);
            return -EFAULT;
        }

        copied++;

        /* Wake up writers */
        wake_up_interruptible(&dev->writeq);
    }

    dev->total_reads += copied;
    mutex_unlock(&dev->lock);

    pr_info("blocking_io_demo: read %zd bytes\n", copied);
    return copied;
}

static const struct file_operations blocking_io_fops = {
    .owner = THIS_MODULE,
    .open = blocking_io_open,
    .release = blocking_io_release,
    .read = blocking_io_read,
    .write = blocking_io_write,
};

/* Probe function */
static int blocking_io_probe(struct platform_device *pdev)
{
    struct blocking_io_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* Initialize buffer */
    dev->head = 0;
    dev->tail = 0;
    dev->count = 0;

    /* Initialize mutex and wait queues */
    mutex_init(&dev->lock);
    init_waitqueue_head(&dev->readq);
    init_waitqueue_head(&dev->writeq);

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        dev_err(&pdev->dev, "failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &blocking_io_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        dev_err(&pdev->dev, "failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!blocking_io_class) {
        blocking_io_class = class_create(driver_name);
        if (IS_ERR(blocking_io_class)) {
            ret = PTR_ERR(blocking_io_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(blocking_io_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    blocking_io_devp = dev;

    dev_info(&pdev->dev, "device registered (buffer size=%d)\n", buffer_size);
    return 0;

err_destroy_class:
    class_destroy(blocking_io_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void blocking_io_remove(struct platform_device *pdev)
{
    struct blocking_io_device *dev = platform_get_drvdata(pdev);

    device_destroy(blocking_io_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "device unregistered\n");
    dev_info(&pdev->dev, "stats: reads=%llu, writes=%llu, read_blocks=%llu, write_blocks=%llu\n",
             dev->total_reads, dev->total_writes,
             dev->read_blocks, dev->write_blocks);
}

/* Device tree match table */
static const struct of_device_id blocking_io_match[] = {
    { .compatible = "imx,blocking-io-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, blocking_io_match);

/* Platform driver */
static struct platform_driver blocking_io_driver = {
    .probe = blocking_io_probe,
    .remove = blocking_io_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = blocking_io_match,
    },
};
module_platform_driver(blocking_io_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Blocking I/O demo driver for Linux 7.0");
MODULE_VERSION("1.0");
