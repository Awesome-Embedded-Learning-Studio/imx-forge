/**
 * @file 20_tutorial_ap3216c_iic_driver_main.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief AP3216C ambient light / proximity / IR sensor driver (modern I2C API)
 * @version 1.0
 * @date 2026-06-20
 *
 * @copyright Copyright (c) 2026
 *
 * An i2c_driver + character device hybrid. The bus layer matches the device
 * tree node "imxaes,ap3216c", probe() wires up /dev/ap3216c and a fresh read
 * from userspace hands back {ir, als, ps} as three unsigned shorts.
 *
 * Written against linux-imx 6.12.49 / mainline 7.1.0: single-argument probe,
 * void remove and single-argument class_create.
 */

#include "ap3216c_hw.h"
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/uaccess.h>

static const char* AP3216C_NAME = "ap3216c";
static const uint8_t AP3216C_CNT = 1;

struct ap3216c_dev {
    struct ap3216c_hw_ctx hw_ctx;  /* chip access + latest sample */
    dev_t devid;
    struct cdev cdev;
    struct class* cls;
    struct device* dev;
};

static int ap3216c_open(struct inode* inode, struct file* filp) {
    /* Recover the device from its embedded cdev so multiple chips coexist. */
    struct ap3216c_dev* dev = container_of(inode->i_cdev, struct ap3216c_dev, cdev);
    filp->private_data = dev;
    return 0;
}

static ssize_t ap3216c_read(struct file* filp, char __user* buf, size_t cnt, loff_t* off) {
    struct ap3216c_dev* dev = filp->private_data;
    unsigned short data[3];

    ap3216c_hw_readdata(&dev->hw_ctx);
    data[0] = dev->hw_ctx.ir;
    data[1] = dev->hw_ctx.als;
    data[2] = dev->hw_ctx.ps;

    if (cnt > sizeof(data)) {
        cnt = sizeof(data);
    }

    if (copy_to_user(buf, data, cnt)) {
        pr_warn("ap3216c: failed to copy sample to user\n");
        return -EFAULT;
    }

    return cnt;
}

static int ap3216c_release(struct inode* inode, struct file* filp) {
    return 0;
}

static const struct file_operations ap3216c_fops = {
    .owner = THIS_MODULE,
    .open = ap3216c_open,
    .read = ap3216c_read,
    .release = ap3216c_release,
};

static int ap3216c_probe(struct i2c_client* client) {
    struct ap3216c_dev* dev;
    int ret;

    dev = devm_kzalloc(&client->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev) {
        return -ENOMEM;
    }

    ret = ap3216c_hw_init(client, &dev->hw_ctx);
    if (ret) {
        dev_err(&client->dev, "failed to init ap3216c hardware: %d\n", ret);
        return ret;
    }

    ret = alloc_chrdev_region(&dev->devid, 0, AP3216C_CNT, AP3216C_NAME);
    if (ret < 0) {
        dev_err(&client->dev, "failed to alloc chrdev region: %d\n", ret);
        goto err_hw;
    }

    cdev_init(&dev->cdev, &ap3216c_fops);
    ret = cdev_add(&dev->cdev, dev->devid, AP3216C_CNT);
    if (ret < 0) {
        dev_err(&client->dev, "failed to add cdev: %d\n", ret);
        goto err_region;
    }

    dev->cls = class_create(AP3216C_NAME);
    if (IS_ERR(dev->cls)) {
        ret = PTR_ERR(dev->cls);
        dev_err(&client->dev, "failed to create class: %d\n", ret);
        goto err_cdev;
    }

    dev->dev = device_create(dev->cls, &client->dev, dev->devid, NULL, AP3216C_NAME);
    if (IS_ERR(dev->dev)) {
        ret = PTR_ERR(dev->dev);
        dev_err(&client->dev, "failed to create device: %d\n", ret);
        goto err_class;
    }

    i2c_set_clientdata(client, dev);
    dev_info(&client->dev, "ap3216c probe success\n");
    return 0;

    /* Kernel error handling is... an acquired taste. */
err_class:
    class_destroy(dev->cls);
err_cdev:
    cdev_del(&dev->cdev);
err_region:
    unregister_chrdev_region(dev->devid, AP3216C_CNT);
err_hw:
    ap3216c_hw_deinit(&dev->hw_ctx);
    return ret;
}

static void ap3216c_remove(struct i2c_client* client) {
    struct ap3216c_dev* dev = i2c_get_clientdata(client);

    device_destroy(dev->cls, dev->devid);
    class_destroy(dev->cls);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->devid, AP3216C_CNT);
    ap3216c_hw_deinit(&dev->hw_ctx);

    dev_info(&client->dev, "ap3216c removed\n");
}

static const struct of_device_id ap3216c_of_match[] = {
    {.compatible = "imxaes,ap3216c"},
    {/* sentinel */},
};
MODULE_DEVICE_TABLE(of, ap3216c_of_match);

static struct i2c_driver ap3216c_driver = {
    .driver =
        {
            .name = "ap3216c",
            .of_match_table = ap3216c_of_match,
        },
    .probe = ap3216c_probe,
    .remove = ap3216c_remove,
};
module_i2c_driver(ap3216c_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("AP3216C ambient light / proximity / IR sensor driver (modern I2C API)");
MODULE_VERSION("1.0");
