#include "linux/fs.h"
#include "linux/uaccess.h"
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/string.h>

static const char* CHARDEV_NAME = "AES_Chardev";
static const int CHARDEV_MAJOR = 200;

#define BUFFER_SIZE (100)
// 注意，还是有一个好习惯，顺手初始化，尽管，static会在上CPU的时候
// 由相关的初始化代码初始化为0
static char buf_read[BUFFER_SIZE] = {0};
static char buf_write[BUFFER_SIZE] = {0};
#undef BUFFER_SIZE

// 这是我们稍后要传递的信息
static const char* kFixedMessage = "Hello from Kernel! Message Sent from the module!";

/* 打开设备 */
static int aes_chardev_open(struct inode* inode, struct file* filp) {
    pr_info("Device: %s called open!\n", CHARDEV_NAME);
    return 0;
}

/* 从设备读取 */
static ssize_t aes_chardev_read(struct file* filp, char __user* buf, size_t cnt, loff_t* offt) {
    pr_info("Device: %s called read!\n", CHARDEV_NAME);
    unsigned int len = strlen(kFixedMessage);

    if (*offt > 0) {
        // `cat` program will request for next session,
        // to avoid always read, break it
        // down.
        return 0;
    }

    if (cnt < len) {
        // Avoid Overflow, for safety reason
        len = cnt;
    }
    // update offsets
    *offt += len;

    memcpy(buf_read, kFixedMessage, strlen(kFixedMessage) + 1);
    const unsigned long kRetValue = copy_to_user(buf, buf_read, len);

    if (kRetValue == 0) {
        pr_info("Successfully Send data to user!\n");
    } else {
        pr_warn("Failed to send data to user, code: %ld", kRetValue);
    }
    return len;
}

/* 向设备写数据 */
static ssize_t aes_chardev_write(struct file* filp, const char __user* buf, size_t cnt,
                                 loff_t* offt) {
    pr_info("Device: %s called write!\n", CHARDEV_NAME);
    // int retvalue = 0;

    size_t len = cnt;

    if (len > sizeof(buf_write) - 1) {
        len = sizeof(buf_write) - 1;
    }

    const unsigned long kRetValue = copy_from_user(buf_write, buf, cnt);
    buf_write[len] = '\0';

    if (kRetValue != 0) {
        pr_warn("Failed to receive data from user, code: %ld\n", kRetValue);
        return -EFAULT;
    }

    pr_info("Kernel module has received from data: %s\r\n", buf_write);
    // And then reset the data buf, for the next session clean
    memset(buf_write, 0, cnt);
    return len;
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

// 模块初始化
static int __init chardev_base_00_init(void) {
    // referenced at: fs/char_dev.c, followed by clangd
    const int kResult = register_chrdev(CHARDEV_MAJOR, CHARDEV_NAME, &fops);
    if (kResult != 0) {
        // If is not Zero, then we failed to do sth
        pr_warn("Failed to register the chardev region! kResult=%d\n", kResult);
        return kResult;
    }

    pr_info("%s load successfully!\n", CHARDEV_NAME);
    return kResult;
}

// 模块退出
static void __exit chardev_base_00_exit(void) {
    pr_info("=== chardev_base_00 module unloaded ===\n");
    unregister_chrdev(CHARDEV_MAJOR, CHARDEV_NAME);
    pr_info("========================\n");
}

module_init(chardev_base_00_init);
module_exit(chardev_base_00_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Basic Char Dev Usage");
MODULE_VERSION("1.0");
