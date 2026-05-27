// SPDX-License-Identifier: GPL-2.0
/*
 * Atomic Operations Demo Driver
 *
 * This driver demonstrates the use of atomic operations in Linux kernel 7.0.
 * It provides a character device interface to test atomic_t and atomic64_t operations.
 *
 * Operations:
 * - read:  Get current counter value and statistics
 * - write: Set counter value or execute atomic operations
 *   Format: "op value" where op is:
 *     'set'   - Set counter to value
 *     'add'   - Add value to counter
 *     'sub'   - Subtract value from counter
 *     'inc'   - Increment counter by 1
 *     'dec'   - Decrement counter by 1
 *
 * Environment: Linux 7.0-rc4, ARMv7-A
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/mutex.h>
#include <linux/atomic.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>

static const char driver_name[] = "atomic_demo";
static const char device_name[] = "atomic_demo";

/* Device structure */
struct atomic_demo_device {
    dev_t dev_num;
    struct cdev cdev;
    struct class *class;
    struct device *device;

    struct mutex lock;

    /* Atomic counters */
    atomic_t counter;
    atomic64_t counter64;

    /* Statistics */
    atomic64_t add_count;
    atomic64_t sub_count;
    atomic64_t inc_count;
    atomic64_t dec_count;
    atomic64_t read_count;
    atomic64_t write_count;
};

static struct atomic_demo_device *atomic_demo_devp;
static struct class *atomic_demo_class;

/* Device operations */
static int atomic_demo_open(struct inode *inode, struct file *file)
{
    struct atomic_demo_device *dev =
        container_of(inode->i_cdev, struct atomic_demo_device, cdev);

    file->private_data = dev;
    atomic64_inc(&dev->read_count);
    return 0;
}

static int atomic_demo_release(struct inode *inode, struct file *file)
{
    return 0;
}

/* Parse command: "op value" */
static int parse_command(const char __user *buf, size_t count,
                        char *op, int *value)
{
    char kbuf[64];
    int ret;
    char *space;

    if (count >= sizeof(kbuf))
        return -EINVAL;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    /* Find space separator */
    space = strchr(kbuf, ' ');
    if (space) {
        *space = '\0';
        strncpy(op, kbuf, 15);
        op[15] = '\0';

        ret = kstrtoint(space + 1, 10, value);
        if (ret)
            return ret;
    } else {
        strncpy(op, kbuf, 15);
        op[15] = '\0';
        *value = 0;
    }

    return 0;
}

static ssize_t atomic_demo_read(struct file *file,
                           char __user *buf,
                           size_t count,
                           loff_t *ppos)
{
    struct atomic_demo_device *dev = file->private_data;
    char kbuf[256];
    int len;
    int val;
    s64 val64;

    mutex_lock(&dev->lock);

    val = atomic_read(&dev->counter);
    val64 = atomic64_read(&dev->counter64);

    len = snprintf(kbuf, sizeof(kbuf),
                   "Atomic Demo Driver Statistics\n"
                   "============================\n"
                   "32-bit counter: %d\n"
                   "64-bit counter: %lld\n"
                   "Operations:\n"
                   "  add   : %lld\n"
                   "  sub   : %lld\n"
                   "  inc   : %lld\n"
                   "  dec   : %lld\n"
                   "  reads : %lld\n"
                   "  writes: %lld\n"
                   "\n"
                   "Commands (write):\n"
                   "  set <value>   - Set counter to value\n"
                   "  add <value>   - Add value to counter\n"
                   "  sub <value>   - Subtract value from counter\n"
                   "  inc           - Increment counter\n"
                   "  dec           - Decrement counter\n",
                   val, val64,
                   atomic64_read(&dev->add_count),
                   atomic64_read(&dev->sub_count),
                   atomic64_read(&dev->inc_count),
                   atomic64_read(&dev->dec_count),
                   atomic64_read(&dev->read_count),
                   atomic64_read(&dev->write_count));

    mutex_unlock(&dev->lock);

    if (*ppos >= len)
        return 0;

    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos = len;
    return len;
}

static ssize_t atomic_demo_write(struct file *file,
                            const char __user *buf,
                            size_t count,
                            loff_t *ppos)
{
    struct atomic_demo_device *dev = file->private_data;
    char op[16];
    int value;
    int ret;

    ret = parse_command(buf, count, op, &value);
    if (ret)
        return ret;

    mutex_lock(&dev->lock);

    if (strcmp(op, "set") == 0) {
        /* Set counter to value */
        atomic_set(&dev->counter, value);
        atomic64_set(&dev->counter64, value);
        pr_info("atomic_demo: counter set to %d\n", value);
    } else if (strcmp(op, "add") == 0) {
        /* Add value to counter */
        atomic_add(value, &dev->counter);
        atomic64_add(value, &dev->counter64);
        atomic64_inc(&dev->add_count);
        pr_info("atomic_demo: added %d, counter = %d\n",
                value, atomic_read(&dev->counter));
    } else if (strcmp(op, "sub") == 0) {
        /* Subtract value from counter */
        atomic_sub(value, &dev->counter);
        atomic64_sub(value, &dev->counter64);
        atomic64_inc(&dev->sub_count);
        pr_info("atomic_demo: subtracted %d, counter = %d\n",
                value, atomic_read(&dev->counter));
    } else if (strcmp(op, "inc") == 0) {
        /* Increment counter */
        atomic_inc(&dev->counter);
        atomic64_inc(&dev->counter64);
        atomic64_inc(&dev->inc_count);
        pr_info("atomic_demo: incremented, counter = %d\n",
                atomic_read(&dev->counter));
    } else if (strcmp(op, "dec") == 0) {
        /* Decrement counter */
        atomic_dec(&dev->counter);
        atomic64_dec(&dev->counter64);
        atomic64_inc(&dev->dec_count);
        pr_info("atomic_demo: decremented, counter = %d\n",
                atomic_read(&dev->counter));
    } else {
        mutex_unlock(&dev->lock);
        return -EINVAL;
    }

    atomic64_inc(&dev->write_count);
    mutex_unlock(&dev->lock);

    return count;
}

static const struct file_operations atomic_demo_fops = {
    .owner = THIS_MODULE,
    .open = atomic_demo_open,
    .release = atomic_demo_release,
    .read = atomic_demo_read,
    .write = atomic_demo_write,
};

/* Probe function */
static int atomic_demo_probe(struct platform_device *pdev)
{
    struct atomic_demo_device *dev;
    int ret;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    /* Initialize atomic counters */
    atomic_set(&dev->counter, 0);
    atomic64_set(&dev->counter64, 0);
    atomic64_set(&dev->add_count, 0);
    atomic64_set(&dev->sub_count, 0);
    atomic64_set(&dev->inc_count, 0);
    atomic64_set(&dev->dec_count, 0);
    atomic64_set(&dev->read_count, 0);
    atomic64_set(&dev->write_count, 0);

    /* Initialize mutex */
    mutex_init(&dev->lock);

    /* Allocate device number */
    ret = alloc_chrdev_region(&dev->dev_num, 0, 1, driver_name);
    if (ret) {
        pr_err("atomic_demo: failed to allocate chrdev region\n");
        return ret;
    }

    /* Initialize character device */
    cdev_init(&dev->cdev, &atomic_demo_fops);
    ret = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (ret) {
        pr_err("atomic_demo: failed to add cdev\n");
        goto err_unregister;
    }

    /* Create device class */
    if (!atomic_demo_class) {
        atomic_demo_class = class_create(driver_name);
        if (IS_ERR(atomic_demo_class)) {
            ret = PTR_ERR(atomic_demo_class);
            goto err_del_cdev;
        }
    }

    /* Create device node */
    dev->device = device_create(atomic_demo_class, &pdev->dev,
                                dev->dev_num, NULL,
                                device_name);
    if (IS_ERR(dev->device)) {
        ret = PTR_ERR(dev->device);
        goto err_destroy_class;
    }

    platform_set_drvdata(pdev, dev);
    atomic_demo_devp = dev;

    pr_info("atomic_demo: device registered\n");
    return 0;

err_destroy_class:
    class_destroy(atomic_demo_class);
err_del_cdev:
    cdev_del(&dev->cdev);
err_unregister:
    unregister_chrdev_region(dev->dev_num, 1);
    return ret;
}

/* Remove function */
static void atomic_demo_remove(struct platform_device *pdev)
{
    struct atomic_demo_device *dev = platform_get_drvdata(pdev);

    device_destroy(atomic_demo_class, dev->dev_num);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    pr_info("atomic_demo: device unregistered\n");
    pr_info("atomic_demo: final counter = %d\n",
            atomic_read(&dev->counter));
}

/* Device tree match table */
static const struct of_device_id atomic_demo_match[] = {
    { .compatible = "imx,atomic-demo" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, atomic_demo_match);

/* Platform driver */
static struct platform_driver atomic_demo_driver = {
    .probe = atomic_demo_probe,
    .remove = atomic_demo_remove,
    .driver = {
        .name = driver_name,
        .of_match_table = atomic_demo_match,
    },
};
module_platform_driver(atomic_demo_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux 7.0 Kernel Tutorial");
MODULE_DESCRIPTION("Atomic operations demo driver for Linux 7.0");
MODULE_VERSION("1.0");
