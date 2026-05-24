// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/gpio/consumer.h>
#include <linux/uaccess.h>
#include <linux/of.h>
#include <linux/types.h>

#define BEEP_NAME       "beep"
static const u8  BEEP_ON  = 0;
static const u8  BEEP_OFF = 1;

struct beep_dev {
    dev_t           dev_num;
    struct cdev     cdev;
    struct class    *class;
    struct device   *device;
    struct gpio_desc *gpio;
};

static struct beep_dev *beep_data;

static int beep_open(struct inode *inode, struct file *filp)
{
    filp->private_data = beep_data;
    pr_info("beep: device opened\n");
    return 0;
}

static int beep_release(struct inode *inode, struct file *filp)
{
    pr_info("beep: device released\n");
    return 0;
}

static ssize_t beep_write(struct file *filp, const char __user *buf,
                          size_t count, loff_t *ppos)
{
    struct beep_dev *dev = filp->private_data;

    if (!dev) {
        return -ENODEV;
    }

    if (count != 1) {
        return -EINVAL;
    }

    u8 val;
    if (copy_from_user(&val, buf, 1)) {
        return -EFAULT;
    }

    if (val == BEEP_ON) {
        gpiod_set_value(dev->gpio, 0);
        pr_info("beep: ON (GPIO set to LOW)\n");
    } else if (val == BEEP_OFF) {
        gpiod_set_value(dev->gpio, 1);
        pr_info("beep: OFF (GPIO set to HIGH)\n");
    } else {
        return -EINVAL;
    }

    return 1;
}

static const struct file_operations beep_fops = {
    .owner   = THIS_MODULE,
    .open    = beep_open,
    .release = beep_release,
    .write   = beep_write,
};

/* 平台驱动 probe 函数 */
static int beep_probe(struct platform_device *pdev)
{
    struct beep_dev *dev;

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev) {
        return -ENOMEM;
    }
    beep_data = dev;

    /* 1. 获取 GPIO（输出高电平初始化，蜂鸣器默认关闭） */
    dev->gpio = devm_gpiod_get(&pdev->dev, "beep", GPIOD_OUT_HIGH);
    if (IS_ERR(dev->gpio)) {
        int err = PTR_ERR(dev->gpio);
        dev_err_probe(&pdev->dev, err, "Failed to get beep GPIO\n");
        return err;
    }

    /* 2. 动态分配设备号 */
    int err = alloc_chrdev_region(&dev->dev_num, 0, 1, BEEP_NAME);
    if (err < 0) {
        dev_err(&pdev->dev, "Failed to allocate device number\n");
        return err;
    }

    /* 3. 初始化并添加 cdev */
    cdev_init(&dev->cdev, &beep_fops);
    dev->cdev.owner = THIS_MODULE;
    err = cdev_add(&dev->cdev, dev->dev_num, 1);
    if (err < 0) {
        dev_err(&pdev->dev, "Failed to add cdev\n");
        goto unregister_region;
    }

    /* 4. 创建类（新版内核仅需类名） */
    dev->class = class_create(BEEP_NAME);
    if (IS_ERR(dev->class)) {
        err = PTR_ERR(dev->class);
        dev_err(&pdev->dev, "Failed to create class\n");
        goto del_cdev;
    }

    /* 5. 创建设备节点 */
    dev->device = device_create(dev->class, NULL, dev->dev_num,
                                NULL, BEEP_NAME);
    if (IS_ERR(dev->device)) {
        err = PTR_ERR(dev->device);
        dev_err(&pdev->dev, "Failed to create device\n");
        goto destroy_class;
    }

    dev_info(&pdev->dev, "Beep driver loaded successfully\n");
    return 0;

destroy_class:
    class_destroy(dev->class);
del_cdev:
    cdev_del(&dev->cdev);
unregister_region:
    unregister_chrdev_region(dev->dev_num, 1);
    return err;
}

/* 平台驱动 remove 函数（新版内核返回 void） */
static void beep_remove(struct platform_device *pdev)
{
    struct beep_dev *dev = beep_data;

    if (!dev) {
        return;
    }

    /* 卸载驱动时确保蜂鸣器关闭 */
    if (dev->gpio) {
        gpiod_set_value(dev->gpio, BEEP_OFF);
        pr_info("beep: turned OFF during driver removal\n");
    }

    device_destroy(dev->class, dev->dev_num);
    class_destroy(dev->class);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->dev_num, 1);

    dev_info(&pdev->dev, "Beep driver removed\n");
}

/* 匹配设备树中的 compatible */
static const struct of_device_id beep_of_match[] = {
    { .compatible = "imxaes,beep" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, beep_of_match);

static struct platform_driver beep_driver = {
    .probe  = beep_probe,
    .remove = beep_remove,
    .driver = {
        .name = "beep",
        .of_match_table = beep_of_match,
    },
};

module_platform_driver(beep_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Tankimko");
MODULE_DESCRIPTION("Beep driver using devm_gpiod_get (new kernel API)");
MODULE_VERSION("1.0");