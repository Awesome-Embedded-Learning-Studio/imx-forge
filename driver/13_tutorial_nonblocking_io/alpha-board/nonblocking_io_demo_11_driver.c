// SPDX-License-Identifier: GPL-2.0
/*
 * Non-blocking I/O & Poll Demo Driver
 *
 * This driver demonstrates non-blocking I/O and poll operations in Linux 7.0.
 * Features:
 * - Bounded buffer implementation (producer-consumer)
 * - Wait queues for reader and writer
 * - Non-blocking read/write operations with O_NONBLOCK
 * - Poll support for select/poll/epoll
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
#include <linux/poll.h>
#include <linux/uaccess.h>
#include <linux/sched/signal.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>

static const char driver_name[] = "nonblocking_io_demo";
static const char device_name[] = "nonblocking_io_demo";
static const int buffer_size = 64;

/* Device structure */
struct nonblocking_io_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;
    wait_queue_head_t readq;
    wait_queue_head_t writeq;

    char buffer[64];
    int head;
    int tail;
    int count;

    /* Statistics */
    u64 total_reads;
    u64 total_writes;
    u64 read_would_blocks;
    u64 write_would_blocks;
    u64 nonblock_reads;
    u64 nonblock_writes;
};

static struct nonblocking_io_device *nonblocking_io_devp;
static struct class *nonblocking_io_class;

/* Check if buffer is empty */
static inline bool is_empty(struct nonblocking_io_device *dev)
{
    return dev->count == 0;
}

/* Check if buffer is full */
static inline bool is_full(struct nonblocking_io_device *dev)
{
    return dev->count == buffer_size;
}

/* Check available space */
static inline int space_avail(struct nonblocking_io_device *dev)
{
    return buffer_size - dev->count;
}

/* Device operations: open */
static int nonblocking_io_open(struct inode *inode, struct file *file)
{
    struct nonblocking_io_device *dev =
        container_of(inode->i_cdev, struct nonblocking_io_device, cdev);

    file->private_data = dev;

    if (file->f_flags & O_NONBLOCK)
        pr_info("nonblocking_io_demo: opened in non-blocking mode\n");
    else
        pr_info("nonblocking_io_demo: opened in blocking mode\n");

    return 0;
}

/* Device operations: release */
static int nonblocking_io_release(struct inode *inode, struct file *file)
{
    pr_info("nonblocking_io_demo: device released\n");
    return 0;
}

/* Poll operation */
static __poll_t nonblocking_io_poll(struct file *file,
                                     poll_table *wait)
{
    struct nonblocking_io_device *dev = file->private_data;
    __poll_t mask = 0;

    mutex_lock(&dev->lock);

    /* Register wait queues */
    poll_wait(file, &dev->readq, wait);
    poll_wait(file, &dev->writeq, wait);

    /* Check readable status */
    if (!is_empty(dev))
        mask |= EPOLLIN | EPOLLRDNORM;

    /* Check writable status */
    if (!is_full(dev))
        mask |= EPOLLOUT | EPOLLWRNORM;

    mutex_unlock(&dev->lock);

    return mask;
}

/* Write data (producer) */
static ssize_t nonblocking_io_write(struct file *file,
                                    const char __user *buf,
                                    size_t count,
                                    loff_t *ppos)
{
    struct nonblocking_io_device *dev = file->private_data;
    ssize_t written = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    while (written < count) {
        /* Non-blocking check */
        if (file->f_flags & O_NONBLOCK && is_full(dev)) {
            dev->write_would_blocks++;
            if (written == 0) {
                written = -EAGAIN;
            }
            break;
        }

        /* Wait for space (blocking mode) */
        if (wait_event_interruptible(dev->writeq, !is_full(dev))) {
            if (written == 0)
                written = -ERESTARTSYS;
            break;
        }

        /* Write a character */
        if (copy_from_user(&ch, buf + written, 1)) {
            written = -EFAULT;
            break;
        }

        dev->buffer[dev->tail] = ch;
        dev->tail = (dev->tail + 1) % buffer_size;
        dev->count++;
        written++;

        /* Track non-blocking writes */
        if (file->f_flags & O_NONBLOCK)
            dev->nonblock_writes++;

        /* Wake up readers */
        wake_up_interruptible(&dev->readq);
    }

    if (written > 0)
        dev->total_writes += written;

    mutex_unlock(&dev->lock);

    pr_info("nonblocking_io_demo: wrote %zd bytes\n", written);
    return written;
}

/* Read data (consumer) */
static ssize_t nonblocking_io_read(struct file *file,
                                   char __user *buf,
                                   size_t count,
                                   loff_t *ppos)
{
    struct nonblocking_io_device *dev = file->private_data;
    ssize_t copied = 0;
    char ch;

    if (count == 0)
        return 0;

    mutex_lock(&dev->lock);

    while (copied < count) {
        /* Non-blocking check */
        if (file->f_flags & O_NONBLOCK && is_empty(dev)) {
            dev->read_would_blocks++;
            if (copied == 0) {
                copied = -EAGAIN;
            }
            break;
        }

        /* Wait for data (blocking mode) */
        if (wait_event_interruptible(dev->readq, !is_empty(dev))) {
            if (copied == 0)
                copied = -ERESTARTSYS;
            break;
        }

        /* Read a character */
        ch = dev->buffer[dev->head];
        dev->head = (dev->head + 1) % buffer_size;
        dev->count--;

        if (copy_to_user(buf + copied, &ch, 1)) {
            copied = -EFAULT;
            break;
        }

        copied++;

        /* Track non-blocking reads */
        if (file->f_flags & O_NONBLOCK)
            dev->nonblock_reads++;

        /* Wake up writers */
        wake_up_interruptible(&dev->writeq);
    }

    if (copied > 0)
        dev->total_reads += copied;

    mutex_unlock(&dev->lock);

    pr_info("nonblocking_io_demo: read %zd bytes\n", copied);
    return copied;
}

static const struct file_operations nonblocking_io_fops = {
    .owner = THIS_MODULE,
    .open = nonblocking_io_open,
    .release = nonblocking_io_release,
    .read = nonblocking_io_read,
    .write = nonblocking_io_write,
    .poll = nonblocking_io_poll,
};

/* Probe function */
static int nonblocking_io_probe(struct platform_device *pdev)
{
    struct nonblocking_io_device *dev;
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
    cdev_init(&dev->cdev, &nonblocking_io_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        dev_err(&pdev->dev, "failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!nonblocking_io_class) {
        nonblocking_io_class = class_create(driver_name);
        if (IS_ERR(nonblocking_io_class)) {
            ret = PTR_ERR(nonblocking_io_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(nonblocking_io_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    nonblocking_io_devp = dev;

    dev_info(&pdev->dev, "device registered (buffer size=%d)\n", buffer_size);
    return 0;

err_destroy_class:
    class_destroy(nonblocking_io_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void nonblocking_io_remove(struct platform_device *pdev)
{
    struct nonblocking_io_device *dev = platform_get_drvdata(pdev);

    device_destroy(nonblocking_io_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "device unregistered\n");
    dev_info(&pdev->dev, "stats: reads=%llu, writes=%llu, read_wb=%llu, write_wb=%llu, nb_reads=%llu, nb_writes=%llu\n",
             dev->total_reads, dev->total_writes,
             dev->read_would_blocks, dev->write_would_blocks,
             dev->nonblock_reads, dev->nonblock_writes);
}

/* Device tree match table */
static const struct of_device_id nonblocking_io_match[] = {
    { .compatible = "imx,nonblocking-io-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, nonblocking_io_match);

/* Platform driver */
static struct platform_driver nonblocking_io_driver = {
    .probe = nonblocking_io_probe,
    .remove = nonblocking_io_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = nonblocking_io_match,
    },
};
module_platform_driver(nonblocking_io_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Non-blocking I/O & poll demo driver for Linux 7.0");
MODULE_VERSION("1.0");
