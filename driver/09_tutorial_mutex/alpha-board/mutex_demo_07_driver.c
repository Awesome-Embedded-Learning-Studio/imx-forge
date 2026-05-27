// SPDX-License-Identifier: GPL-2.0
/*
 * Mutex Demo Driver
 *
 * This driver demonstrates the use of mutexes in Linux kernel 7.0.
 * Mutex allows sleeping in critical sections, unlike spinlocks.
 *
 * Environment: Linux 7.0-rc4, ARMv7-A
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/mutex.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/kthread.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>
#include <linux/math64.h>

static const char driver_name[] = "mutex_demo";
static const char device_name[] = "mutex_demo";

/* Device structure */
struct mutex_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex mutex;
    struct mutex read_mutex;
    struct mutex write_mutex;

    int shared_data;
    int readers_active;
    int writers_active;

    /* Statistics */
    u64 read_count;
    u64 write_count;
    u64 lock_wait_ns;
};

static struct mutex_device *mutex_devp;
static struct class *mutex_class;

/* Simulate slow operation (can sleep) */
static void slow_operation(void)
{
    /* Mutex allows sleeping */
    msleep(10);
}

/* Protected read */
static int protected_read(struct mutex_device *dev, int *value)
{
    u64 start;

    start = ktime_get_ns();

    /* Read mutex - multiple readers can hold this */
    mutex_lock(&dev->read_mutex);
    dev->readers_active++;

    /* Check if writer is active */
    if (dev->writers_active > 0) {
        dev->readers_active--;
        mutex_unlock(&dev->read_mutex);
        return -EBUSY;
    }

    /* Read data */
    *value = dev->shared_data;
    dev->read_count++;

    dev->readers_active--;
    mutex_unlock(&dev->read_mutex);

    dev->lock_wait_ns += ktime_get_ns() - start;
    return 0;
}

/* Protected write */
static int protected_write(struct mutex_device *dev, int value)
{
    u64 start;

    start = ktime_get_ns();

    /* Write mutex - exclusive access */
    mutex_lock(&dev->write_mutex);
    mutex_lock(&dev->mutex);

    dev->writers_active++;

    /* Simulate slow operation */
    slow_operation();

    dev->shared_data = value;
    dev->write_count++;

    dev->writers_active--;
    mutex_unlock(&dev->mutex);
    mutex_unlock(&dev->write_mutex);

    dev->lock_wait_ns += ktime_get_ns() - start;
    return 0;
}

/* Device operations */
static int mutex_open(struct inode *inode, struct file *file)
{
    struct mutex_device *dev =
        container_of(inode->i_cdev, struct mutex_device, cdev);

    file->private_data = dev;
    return 0;
}

static int mutex_demo_release(struct inode *inode, struct file *file)
{
    return 0;
}

static ssize_t mutex_read(struct file *file,
                          char __user *buf,
                          size_t count,
                          loff_t *ppos)
{
    struct mutex_device *dev = file->private_data;
    char kbuf[256];
    int len;
    int value;

    /* Try to read shared data */
    if (protected_read(dev, &value) == 0) {
        len = snprintf(kbuf, sizeof(kbuf),
                       "Mutex Demo Driver\n"
                       "==================\n"
                       "Shared data: %d\n"
                       "Readers active: %d\n"
                       "Writers active: %d\n"
                       "Total reads: %llu\n"
                       "Total writes: %llu\n"
                       "Avg lock wait: %llu ns\n"
                       "\n"
                       "Commands (write):\n"
                       "  write <value> - Write value to shared data\n"
                       "  slow_write <value> - Write with delay (demonstrates sleeping)\n",
                       value, dev->readers_active, dev->writers_active,
                       dev->read_count, dev->write_count,
                       dev->read_count > 0 ? div64_u64(dev->lock_wait_ns, dev->read_count) : 0);
    } else {
        len = snprintf(kbuf, sizeof(kbuf),
                       "Mutex Demo Driver\n"
                       "==================\n"
                       "Error: Writer active\n");
    }

    if (*ppos >= len)
        return 0;

    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos = len;
    return len;
}

static ssize_t mutex_write(struct file *file,
                           const char __user *buf,
                           size_t count,
                           loff_t *ppos)
{
    struct mutex_device *dev = file->private_data;
    char kbuf[64];
    char op[32];
    int value;
    int ret;

    if (count >= sizeof(kbuf))
        return -EINVAL;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    ret = sscanf(kbuf, "%s %d", op, &value);
    if (ret < 2)
        return -EINVAL;

    if (strcmp(op, "write") == 0) {
        protected_write(dev, value);
        pr_info("mutex_demo: wrote value %d\n", value);
    } else if (strcmp(op, "slow_write") == 0) {
        protected_write(dev, value);
        pr_info("mutex_demo: slow wrote value %d\n", value);
    } else {
        return -EINVAL;
    }

    return count;
}

static const struct file_operations mutex_fops = {
    .owner = THIS_MODULE,
    .open = mutex_open,
    .release = mutex_demo_release,
    .read = mutex_read,
    .write = mutex_write,
};

/* Probe function */
static int mutex_probe(struct platform_device *pdev)
{
    struct mutex_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* Initialize mutexes */
    mutex_init(&dev->mutex);
    mutex_init(&dev->read_mutex);
    mutex_init(&dev->write_mutex);

    dev->shared_data = 0;
    dev->readers_active = 0;
    dev->writers_active = 0;

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        pr_err("mutex_demo: failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &mutex_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("mutex_demo: failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!mutex_class) {
        mutex_class = class_create(driver_name);
        if (IS_ERR(mutex_class)) {
            ret = PTR_ERR(mutex_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(mutex_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    mutex_devp = dev;

    pr_info("mutex_demo: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(mutex_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void mutex_remove(struct platform_device *pdev)
{
    struct mutex_device *dev = platform_get_drvdata(pdev);

    device_destroy(mutex_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("mutex_demo: device unregistered\n");
}

/* Device tree match table */
static const struct of_device_id mutex_match[] = {
    { .compatible = "imx,mutex-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, mutex_match);

/* Platform driver */
static struct platform_driver mutex_driver = {
    .probe = mutex_probe,
    .remove = mutex_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = mutex_match,
    },
};
module_platform_driver(mutex_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Mutex demo driver for Linux 7.0");
MODULE_VERSION("1.0");
