/**
 * @file chardev_led_v2_02_driver_main.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED Driver using new API
 * @version 0.1
 * @date 2026-04-18
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "led_hw.h"
#include "linux/printk.h"
#include <linux/cdev.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/uaccess.h>

static const char* CHARDEV_NAME = "AES_LED";
static const int LED_CNT = 1;

struct IMXAesLED {
    dev_t devid;
    struct cdev char_device_handle;
    struct class* char_device_class;
    struct device* char_device_device;
} led_handle;

static int aes_chardev_open(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
    // Assigned the private data
    filp->private_data = &led_handle;
    return 0;
}

static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    // Upper Level App request to read the application

    if (*offt > 0) {
        // `cat` program will request for next session,
        // to avoid always read, break it
        // down.
        return 0;
    }

    if (cnt > 1) {
        cnt = 1;
    }

    *offt += cnt;

    // let make these simple
    // '1' for on, '0' for close
    const bool led_status = led_get_status();
    const char user_indication = led_status ? '1' : '0';

    const auto kResult = copy_to_user(buf, &user_indication, cnt);
    if (kResult != 0) {
        pr_warn("Failed to pass the led status to user! code: %ld\n", kResult);
        return -EFAULT;
    }

    return cnt;
}

static ssize_t aes_chardev_write(struct file* filp, const char __user* buf, size_t cnt,
                                 loff_t* offt) {
    pr_info("aes_chardev_write: cnt=%zu\n", cnt);

    if (cnt > 2) {
        pr_warn("Get the unexpected data, thats to more!\n");
        return -EINVAL;
    }

    char user_led_new_status = 0;
    const auto kResult = copy_from_user(&user_led_new_status, buf, 1);
    if (kResult != 0) {
        pr_warn("Failed to set the led status from user! code: %ld\n", kResult);
        return -EFAULT;
    }

    const bool led_new_status = (user_led_new_status == '1') ? true : false;
    pr_info("LED status: %d (user_led_new_status='%c')\n", led_new_status, user_led_new_status);
    led_set_status(led_new_status);
    return 1;
}

/* 关闭/释放设备 */
static int aes_chardev_release(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called close!\n", CHARDEV_NAME);
    filp->private_data = NULL; // Release the private datas
    return 0;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = aes_chardev_open,
    .read = aes_chardev_read,
    .write = aes_chardev_write,
    .release = aes_chardev_release,
};

static int init_led_handle(struct IMXAesLED* led_handle) {
    // filled the led handle, by using new API
    pr_info("Init the User Interfaces and driver handles\n");

    // Calling for a major dev number
    alloc_chrdev_region(&led_handle->devid, 0, LED_CNT, CHARDEV_NAME);

    // I do not like the var leak, so, just do this as I like :)
    {
        const auto led_major_number = MAJOR(led_handle->devid);
        const auto led_minor_number = MINOR(led_handle->devid);

        pr_info("LED handle get the device number: major: %u, minor: %u\n", led_major_number,
                led_minor_number);
    }

    led_handle->char_device_handle.owner = THIS_MODULE;
    cdev_init(&led_handle->char_device_handle, &fops);
    const auto kResult = cdev_add(&led_handle->char_device_handle, led_handle->devid, LED_CNT);
    if (kResult < 0) {
        pr_warn("Error when trying to make a cdev in kernel: %d\n", kResult);
        return kResult;
    }

    pr_info("cdev series api called success!\n");

    // Mark: New kernel has abolished the owner module
    led_handle->char_device_class = class_create(CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_class)) {
        const auto error_code = PTR_ERR(led_handle->char_device_class);
        pr_warn("Failed to create a class, code: %ld", error_code);
        return error_code;
    }

    pr_info("class create success!\n");

    led_handle->char_device_device =
        device_create(led_handle->char_device_class, NULL, led_handle->devid, NULL, CHARDEV_NAME);
    if (IS_ERR(led_handle->char_device_device)) {
        const auto error_code = PTR_ERR(led_handle->char_device_device);
        pr_warn("Failed to create a class, code: %ld", error_code);
        return error_code;
    }

    pr_info("device create success!\n");
    return 0;
}

static void release_led_handle(struct IMXAesLED* led_handle) {
    device_destroy(led_handle->char_device_class, led_handle->devid);
    class_destroy(led_handle->char_device_class);
    cdev_del(&led_handle->char_device_handle);
    unregister_chrdev_region(led_handle->devid, LED_CNT);
}

static int __init chardev_led_v2_02_init(void) {
    pr_info("=== led driver using new api ===\n");
    led_hw_init();
    // init the handle
    init_led_handle(&led_handle);
    pr_info("========================\n");
    return 0;
}

static void __exit chardev_led_v2_02_exit(void) {
    pr_info("=== chardev_led_v2_02驱动卸载成功 ===\n");
    release_led_handle(&led_handle);
    led_hw_deinit();
    pr_info("========================\n");
}

module_init(chardev_led_v2_02_init);
module_exit(chardev_led_v2_02_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("led driver using new api");
MODULE_VERSION("1.0");
