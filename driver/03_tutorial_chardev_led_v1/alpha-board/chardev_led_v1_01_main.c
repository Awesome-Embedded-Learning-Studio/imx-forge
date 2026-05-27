/**
 * @file chardev_led_v1_01_driver.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED Driver For Version 1
 * @version 0.1
 * @date 2026-04-18
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "led_hw.h"
#include "linux/fs.h"
#include "linux/printk.h"
#include "linux/uaccess.h"
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static const char* CHARDEV_NAME = "AES_LED";
static const int CHARDEV_MAJOR = 200;

static int aes_chardev_open(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
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
    return 0;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = aes_chardev_open,
    .read = aes_chardev_read,
    .write = aes_chardev_write,
    .release = aes_chardev_release,
};

static int __init chardev_led_v1_01_init(void) {
    led_hw_init();
    const int kResult = register_chrdev(CHARDEV_MAJOR, CHARDEV_NAME, &fops);
    if (kResult != 0) {
        pr_warn("Failed to register the chardev region! kResult=%d\n", kResult);
        return kResult;
    }

    pr_info("%s load successfully!\n", CHARDEV_NAME);
    return kResult;
}

static void __exit chardev_led_v1_01_exit(void) {
    pr_info("=== chardev_led_v1_01 rmmod progress ===\n");
    led_hw_deinit();
    unregister_chrdev(CHARDEV_MAJOR, CHARDEV_NAME);
    pr_info("========================\n");
}

module_init(chardev_led_v1_01_init);
module_exit(chardev_led_v1_01_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("led driver using raw addr");
MODULE_VERSION("1.0");
