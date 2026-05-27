/**
 * @file 17_tutorial_key_driver.c
 * @author Charliechen114514
 * @brief Tutorial 17: Basic Key Driver (GPIO Polling, No Debounce)
 * @version 0.1
 * @date 2026-05-27
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/atomic.h>
#include <linux/of.h>

#include "key_hw.h"

#define DEVICE_NAME "imxaes_key"
#define CLASS_NAME "imxaes_key_class"
#define DRIVER_NAME "imxaes-key-gpio"

struct key_gpio_dev {
    dev_t devid;
    struct cdev cdev;
    struct class *class;
    struct device *device;
    int major;
    struct gpio_desc *gpio;
    atomic_t keyvalue;
};

static struct key_gpio_dev *key_dev;

static int key_open(struct inode *inode, struct file *file);
static int key_release(struct inode *inode, struct file *file);
static ssize_t key_read(struct file *file, char __user *buf, size_t count, loff_t *ppos);

static const struct file_operations key_fops = {
    .owner = THIS_MODULE,
    .open = key_open,
    .release = key_release,
    .read = key_read,
};

static int key_open(struct inode *inode, struct file *file)
{
    file->private_data = key_dev;
    pr_info("key_open: device opened\n");
    return 0;
}

static int key_release(struct inode *inode, struct file *file)
{
    pr_info("key_release: device closed\n");
    return 0;
}

static ssize_t key_read(struct file *file, char __user *buf, size_t count, loff_t *ppos)
{
    struct key_gpio_dev *dev = file->private_data;
    int last_state, current_state;

    if (count < sizeof(int)) {
        pr_err("key_read: buffer too small\n");
        return -EINVAL;
    }

    /* Get current tutorial state: 0=pressed, 1=released */
    last_state = key_get_state(dev->gpio);

    /* Wait for GPIO state change */
    while (1) {
        /* Check for signals (Ctrl+C) */
        if (signal_pending(current)) {
            return -ERESTARTSYS;
        }

        current_state = key_get_state(dev->gpio);
        if (current_state != last_state) {
            /* Return the app convention: 1=pressed, 0=released */
            int key_value = !current_state;
            if (copy_to_user(buf, &key_value, sizeof(key_value))) {
                pr_err("key_read: copy_to_user failed\n");
                return -EFAULT;
            }
            return sizeof(key_value);
        }
        schedule();
    }
}

static int key_probe(struct platform_device *pdev)
{
    int ret;

    pr_info("key_probe: probing device\n");

    key_dev = kzalloc(sizeof(*key_dev), GFP_KERNEL);
    if (!key_dev) {
        pr_err("key_probe: failed to allocate memory\n");
        return -ENOMEM;
    }

    atomic_set(&key_dev->keyvalue, 1);

    ret = key_hw_init(&pdev->dev, &key_dev->gpio);
    if (ret) {
        pr_err("key_probe: key_hw_init failed\n");
        goto err_free_dev;
    }

    ret = alloc_chrdev_region(&key_dev->devid, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        pr_err("key_probe: alloc_chrdev_region failed\n");
        goto err_hw_deinit;
    }
    key_dev->major = MAJOR(key_dev->devid);

    cdev_init(&key_dev->cdev, &key_fops);
    ret = cdev_add(&key_dev->cdev, key_dev->devid, 1);
    if (ret) {
        pr_err("key_probe: cdev_add failed\n");
        goto err_unregister_chrdev;
    }

    key_dev->class = class_create(CLASS_NAME);
    if (IS_ERR(key_dev->class)) {
        pr_err("key_probe: class_create failed\n");
        ret = PTR_ERR(key_dev->class);
        goto err_cdev_del;
    }

    key_dev->device = device_create(key_dev->class, &pdev->dev,
                                     key_dev->devid, NULL, DEVICE_NAME);
    if (IS_ERR(key_dev->device)) {
        pr_err("key_probe: device_create failed\n");
        ret = PTR_ERR(key_dev->device);
        goto err_class_destroy;
    }

    platform_set_drvdata(pdev, key_dev);
    pr_info("key_probe: device registered as %s (major %d)\n",
            DEVICE_NAME, key_dev->major);

    return 0;

err_class_destroy:
    class_destroy(key_dev->class);
err_cdev_del:
    cdev_del(&key_dev->cdev);
err_unregister_chrdev:
    unregister_chrdev_region(key_dev->devid, 1);
err_hw_deinit:
    key_hw_deinit(key_dev->gpio);
err_free_dev:
    kfree(key_dev);
    return ret;
}

static void key_remove(struct platform_device *pdev)
{
    struct key_gpio_dev *dev = platform_get_drvdata(pdev);

    pr_info("key_remove: removing device\n");

    if (dev) {
        device_destroy(dev->class, dev->devid);
        class_destroy(dev->class);
        cdev_del(&dev->cdev);
        unregister_chrdev_region(dev->devid, 1);
        key_hw_deinit(dev->gpio);
        kfree(dev);
    }

    pr_info("key_remove: device removed\n");
}

static const struct of_device_id key_of_match[] = {
    { .compatible = DRIVER_NAME },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, key_of_match);

static struct platform_driver key_platform_driver = {
    .probe = key_probe,
    .remove = key_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = key_of_match,
    },
};

module_platform_driver(key_platform_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Tutorial 17: Basic GPIO Key Driver (No Debounce)");
MODULE_VERSION("0.1");
