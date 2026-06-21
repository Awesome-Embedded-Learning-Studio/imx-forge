/**
 * @file 21_tutorial_icm20608_spi_driver_main.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief ICM-20608 6-axis IMU driver (modern SPI API)
 * @version 1.0
 * @date 2026-06-20
 *
 * @copyright Copyright (c) 2026
 *
 * A spi_driver + character device hybrid. The bus layer matches the device
 * tree node "imxaes,icm20608", probe() wires up /dev/icm20608 and a fresh
 * read from userspace hands back {gx, gy, gz, ax, ay, az, temp} as seven
 * signed ints (raw ADC, conversion is left to the test program).
 *
 * Written against linux-imx 6.12.49 / mainline 7.1.0: single-argument probe,
 * void remove and single-argument class_create.
 */

#include "icm20608_hw.h"
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/spi/spi.h>
#include <linux/uaccess.h>

static const char* ICM20608_NAME = "icm20608";
static const uint8_t ICM20608_CNT = 1;

struct icm20608_dev {
    struct icm20608_hw_ctx hw_ctx;  /* chip access + latest sample */
    dev_t devid;
    struct cdev cdev;
    struct class* cls;
    struct device* dev;
};

static int icm20608_open(struct inode* inode, struct file* filp) {
    /* Recover the device from its embedded cdev so multiple chips coexist. */
    struct icm20608_dev* dev = container_of(inode->i_cdev, struct icm20608_dev, cdev);
    filp->private_data = dev;
    return 0;
}

static ssize_t icm20608_read(struct file* filp, char __user* buf, size_t cnt, loff_t* off) {
    struct icm20608_dev* dev = filp->private_data;
    signed int data[7];

    icm20608_hw_readdata(&dev->hw_ctx);
    data[0] = dev->hw_ctx.gyro_x_adc;
    data[1] = dev->hw_ctx.gyro_y_adc;
    data[2] = dev->hw_ctx.gyro_z_adc;
    data[3] = dev->hw_ctx.accel_x_adc;
    data[4] = dev->hw_ctx.accel_y_adc;
    data[5] = dev->hw_ctx.accel_z_adc;
    data[6] = dev->hw_ctx.temp_adc;

    if (cnt > sizeof(data)) {
        cnt = sizeof(data);
    }

    if (copy_to_user(buf, data, cnt)) {
        pr_warn("icm20608: failed to copy sample to user\n");
        return -EFAULT;
    }

    return cnt;
}

static int icm20608_release(struct inode* inode, struct file* filp) {
    return 0;
}

static const struct file_operations icm20608_fops = {
    .owner = THIS_MODULE,
    .open = icm20608_open,
    .read = icm20608_read,
    .release = icm20608_release,
};

static int icm20608_probe(struct spi_device* spi) {
    struct icm20608_dev* dev;
    int ret;

    dev = devm_kzalloc(&spi->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev) {
        return -ENOMEM;
    }

    ret = icm20608_hw_init(spi, &dev->hw_ctx);
    if (ret) {
        dev_err(&spi->dev, "failed to init icm20608 hardware: %d\n", ret);
        return ret;
    }

    ret = alloc_chrdev_region(&dev->devid, 0, ICM20608_CNT, ICM20608_NAME);
    if (ret < 0) {
        dev_err(&spi->dev, "failed to alloc chrdev region: %d\n", ret);
        goto err_hw;
    }

    cdev_init(&dev->cdev, &icm20608_fops);
    ret = cdev_add(&dev->cdev, dev->devid, ICM20608_CNT);
    if (ret < 0) {
        dev_err(&spi->dev, "failed to add cdev: %d\n", ret);
        goto err_region;
    }

    dev->cls = class_create(ICM20608_NAME);
    if (IS_ERR(dev->cls)) {
        ret = PTR_ERR(dev->cls);
        dev_err(&spi->dev, "failed to create class: %d\n", ret);
        goto err_cdev;
    }

    dev->dev = device_create(dev->cls, &spi->dev, dev->devid, NULL, ICM20608_NAME);
    if (IS_ERR(dev->dev)) {
        ret = PTR_ERR(dev->dev);
        dev_err(&spi->dev, "failed to create device: %d\n", ret);
        goto err_class;
    }

    spi_set_drvdata(spi, dev);
    dev_info(&spi->dev, "icm20608 probe success\n");
    return 0;

    /* Kernel error handling is... an acquired taste. */
err_class:
    class_destroy(dev->cls);
err_cdev:
    cdev_del(&dev->cdev);
err_region:
    unregister_chrdev_region(dev->devid, ICM20608_CNT);
err_hw:
    icm20608_hw_deinit(&dev->hw_ctx);
    return ret;
}

static void icm20608_remove(struct spi_device* spi) {
    struct icm20608_dev* dev = spi_get_drvdata(spi);

    device_destroy(dev->cls, dev->devid);
    class_destroy(dev->cls);
    cdev_del(&dev->cdev);
    unregister_chrdev_region(dev->devid, ICM20608_CNT);
    icm20608_hw_deinit(&dev->hw_ctx);

    dev_info(&spi->dev, "icm20608 removed\n");
}

static const struct of_device_id icm20608_of_match[] = {
    {.compatible = "imxaes,icm20608"},
    {/* sentinel */},
};
MODULE_DEVICE_TABLE(of, icm20608_of_match);

static struct spi_driver icm20608_driver = {
    .driver =
        {
            .name = "icm20608",
            .of_match_table = icm20608_of_match,
        },
    .probe = icm20608_probe,
    .remove = icm20608_remove,
};
module_spi_driver(icm20608_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("ICM-20608 6-axis IMU driver (modern SPI API)");
MODULE_VERSION("1.0");
