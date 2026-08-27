// SPDX-License-Identifier: GPL-2.0
/*
 * hello_mod.c — the "hello world" of board bring-up on the emulated AES board
 *
 * Registers a misc character device; every read() returns one line with the
 * kernel uptime, so userspace can prove it is talking to THIS kernel on
 * THIS boot. Pair with hello_app.c.
 *
 * Build:   make            (kernel module + static app)
 * Deploy:  make install    (drops both into ~/tftp, shared with the real
 *                           board's netboot workflow)
 * Run:     tftp -g -r hello_mod.ko 10.0.2.2 && insmod hello_mod.ko
 *          tftp -g -r hello_app 10.0.2.2 && chmod +x hello_app && ./hello_app
 */

#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/time64.h>
#include <linux/math64.h>

static ssize_t hello_read(struct file *filp, char __user *buf,
                          size_t count, loff_t *off)
{
    char msg[64];
    int len;
    u64 uptime_ns = ktime_get_boottime_ns();

    /* *off != 0 means userspace is calling read() a second time on the
     * same "file position": report EOF so cat/read loops terminate. */
    if (*off != 0) {
        return 0;
    }

    /* 32-bit ARM has no u64/u64 divide in modules (would need libgcc's
     * __aeabi_uldivmod) — do_div() is the kernel-native way. */
    {
        u64 centis = uptime_ns;
        unsigned int rem = do_div(centis, NSEC_PER_SEC / 100);

        (void)rem;
        len = scnprintf(msg, sizeof(msg),
                        "hello from the emulated AES board kernel, uptime %llu.%02llu s\n",
                        centis / 100, centis % 100);
    }

    if (count < len) {
        return -EINVAL;
    }
    if (copy_to_user(buf, msg, len)) {
        return -EFAULT;
    }

    *off = len;
    return len;
}

static const struct file_operations hello_fops = {
    .owner = THIS_MODULE,
    .read  = hello_read,
};

static struct miscdevice hello_misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name  = "hello",
    .fops  = &hello_fops,
};

static int __init hello_init(void)
{
    int ret = misc_register(&hello_misc);

    if (ret) {
        pr_err("hello: misc_register failed: %d\n", ret);
        return ret;
    }

    pr_info("hello: /dev/hello ready — try: cat /dev/hello\n");
    return 0;
}

static void __exit hello_exit(void)
{
    misc_deregister(&hello_misc);
    pr_info("hello: goodbye\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Hello-world misc device for the emulated AES board");
MODULE_AUTHOR("imx-forge");
