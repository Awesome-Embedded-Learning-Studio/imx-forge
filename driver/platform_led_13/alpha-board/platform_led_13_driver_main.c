/**
 * @file platform_led_13_driver.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED driver using platform API
 * @version 1.0
 * @date 2026-05-24
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "led_hw.h"
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/printk.h>
#include <linux/uaccess.h>

static const char* IMX_LED_NAME = "AES_LED";
static const uint8_t LED_CNT = 1;

struct platform_led {
    struct led_hw_ctx hw_ctx;
    dev_t devid;
    struct cdev cdev;
    struct class* cls;
    struct device* dev;
};

static struct platform_led* g_led;

static int aes_led_open(struct inode* inode, struct file* filp) {
    pr_info("AES LED: open\n");
    return 0;
}

static ssize_t aes_led_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    if (*offt > 0) {
        return 0;
    }

    if (cnt > 1) {
        cnt = 1;
    }

    *offt += cnt;

    bool status = led_get_status(&g_led->hw_ctx);
    char value = status ? '1' : '0';

    if (copy_to_user(buf, &value, cnt)) {
        pr_warn("Failed to copy to user\n");
        return -EFAULT;
    }

    return cnt;
}

static ssize_t aes_led_write(struct file* filp, const char __user* buf, size_t cnt, loff_t* offt) {
    char value;

    if (cnt > 1) {
        return -EINVAL;
    }

    if (copy_from_user(&value, buf, 1)) {
        pr_warn("Failed to copy from user\n");
        return -EFAULT;
    }

    bool status = (value == '1');
    led_set_status(&g_led->hw_ctx, status);

    return 1;
}

static int aes_led_release(struct inode* inode, struct file* filp) {
    pr_info("AES LED: release\n");
    return 0;
}

static struct file_operations aes_led_fops = {
    .owner = THIS_MODULE,
    .open = aes_led_open,
    .read = aes_led_read,
    .write = aes_led_write,
    .release = aes_led_release,
};

static int platform_led_probe(struct platform_device* pdev) {
    int ret;

    pr_info("platform_led: probe\n");

    g_led = devm_kzalloc(&pdev->dev, sizeof(*g_led), GFP_KERNEL);
    if (!g_led) {
        return -ENOMEM;
    }

    ret = led_hw_init(&pdev->dev, &g_led->hw_ctx);
    if (ret) {
        dev_err(&pdev->dev, "Failed to init LED hardware: %d\n", ret);
        return ret;
    }

    ret = alloc_chrdev_region(&g_led->devid, 0, LED_CNT, IMX_LED_NAME);
    if (ret < 0) {
        dev_err(&pdev->dev, "Failed to alloc chrdev region: %d\n", ret);
        goto err_hw;
    }

    cdev_init(&g_led->cdev, &aes_led_fops);
    ret = cdev_add(&g_led->cdev, g_led->devid, LED_CNT);
    if (ret < 0) {
        dev_err(&pdev->dev, "Failed to add cdev: %d\n", ret);
        goto err_region;
    }

    g_led->cls = class_create(IMX_LED_NAME);
    if (IS_ERR(g_led->cls)) {
        ret = PTR_ERR(g_led->cls);
        dev_err(&pdev->dev, "Failed to create class: %d\n", ret);
        goto err_cdev;
    }

    g_led->dev = device_create(g_led->cls, &pdev->dev, g_led->devid, NULL, IMX_LED_NAME);
    if (IS_ERR(g_led->dev)) {
        ret = PTR_ERR(g_led->dev);
        dev_err(&pdev->dev, "Failed to create device: %d\n", ret);
        goto err_class;
    }

    platform_set_drvdata(pdev, g_led);
    dev_info(&pdev->dev, "platform_led probe success\n");

    return 0;

    /* 内核错误处理的确有点，难以评鉴 */
err_class:
    class_destroy(g_led->cls);
err_cdev:
    cdev_del(&g_led->cdev);
err_region:
    unregister_chrdev_region(g_led->devid, LED_CNT);
err_hw:
    led_hw_deinit(&g_led->hw_ctx);
    return ret;
}

static void platform_led_remove(struct platform_device* pdev) {
    struct platform_led* led = platform_get_drvdata(pdev);

    pr_info("platform_led: remove\n");

    if (led) {
        device_destroy(led->cls, led->devid);
        class_destroy(led->cls);
        cdev_del(&led->cdev);
        unregister_chrdev_region(led->devid, LED_CNT);
        led_hw_deinit(&led->hw_ctx);
    }

    dev_info(&pdev->dev, "platform_led removed\n");
}

static const struct of_device_id led_of_match[] = {
    {.compatible = "imxaes,led"},
    {/* sentinel */},
};
MODULE_DEVICE_TABLE(of, led_of_match);

static struct platform_driver platform_led_driver = {
    .probe = platform_led_probe,
    .remove = platform_led_remove,
    .driver =
        {
            .name = "platform_led_13",
            .of_match_table = led_of_match,
        },
};

module_platform_driver(platform_led_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("LED Driver using platform API");
MODULE_VERSION("1.0");
