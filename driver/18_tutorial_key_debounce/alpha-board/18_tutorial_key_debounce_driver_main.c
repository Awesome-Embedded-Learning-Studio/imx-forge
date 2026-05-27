/**
 * @file 18_tutorial_key_debounce_driver.c
 * @author Charliechen114514
 * @brief Tutorial 18: Debounced Key Driver (Interrupt + Work Queue)
 *        Demonstrates proper debouncing using interrupt and work queue.
 *        The interrupt triggers on both edges, schedules a work queue
 *        that waits 20ms for the signal to stabilize before reading.
 * @version 0.1
 * @date 2026-05-27
 */

#include <linux/cdev.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/poll.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/wait.h>
#include <linux/workqueue.h>

#include "key_hw.h"

#define DEVICE_NAME "imxaes_key_debounce"
#define CLASS_NAME "imxaes_key_debounce_class"
#define DRIVER_NAME "imxaes-key-debounce"
#define DEBOUNCE_MS 20

/* Device structure */
struct key_debounce_dev {
    dev_t devid;
    struct cdev cdev;
    struct class* class;
    struct device* device;
    int major;

    /* Hardware */
    struct gpio_desc* gpio;
    int irq;

    /* Work queue for debounce */
    struct work_struct work;

    /* State tracking */
    spinlock_t lock;
    int last_gpio_state;
    bool event_ready;
    int key_value;

    /* Wait queue for blocking read */
    wait_queue_head_t waitq;

    /* Statistics (for educational purposes) */
    atomic_t irq_count;
    atomic_t event_count;
    atomic_t debounce_skipped;
};

static struct key_debounce_dev* key_dev;

/* Function prototypes */
static int key_open(struct inode* inode, struct file* file);
static int key_release(struct inode* inode, struct file* file);
static ssize_t key_read(struct file* file, char __user* buf, size_t count, loff_t* ppos);
static __poll_t key_poll(struct file* file, struct poll_table_struct* pt);

static const struct file_operations key_fops = {
    .owner = THIS_MODULE,
    .open = key_open,
    .release = key_release,
    .read = key_read,
    .poll = key_poll,
};

/**
 * @brief Work queue handler - performs debounce delay and state check
 */
static void key_work_handler(struct work_struct* work) {
    struct key_debounce_dev* dev = container_of(work, struct key_debounce_dev, work);
    int current_state;
    unsigned long flags;

    /* Debounce delay - wait for mechanical bounce to settle */
    msleep_interruptible(DEBOUNCE_MS);

    /* Read the stable tutorial state: 0=pressed, 1=released */
    current_state = key_get_state(dev->gpio);

    spin_lock_irqsave(&dev->lock, flags);

    /* Only generate event if state actually changed */
    if (current_state != dev->last_gpio_state) {
        dev->last_gpio_state = current_state;
        /* Return the app convention: 1=pressed, 0=released */
        dev->key_value = !current_state;
        dev->event_ready = true;
        wake_up_interruptible(&dev->waitq);
        atomic_inc(&dev->event_count);
        pr_debug("key_work: event generated, state=%d\n", current_state);
    } else {
        /* State unchanged after debounce - skip this event */
        atomic_inc(&dev->debounce_skipped);
        pr_debug("key_work: bounce skipped\n");
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}

/**
 * @brief Interrupt handler - top half, schedules work queue
 */
static irqreturn_t key_irq_handler(int irq, void* dev_id) {
    struct key_debounce_dev* dev = dev_id;

    atomic_inc(&dev->irq_count);

    /* Schedule work queue for debounce processing */
    schedule_work(&dev->work);

    return IRQ_HANDLED;
}

/**
 * @brief Open - initialize private data
 */
static int key_open(struct inode* inode, struct file* file) {
    file->private_data = key_dev;
    pr_info("key_open: device opened\n");
    return 0;
}

/**
 * @brief Release - cleanup
 */
static int key_release(struct inode* inode, struct file* file) {
    pr_info("key_release: device closed\n");
    return 0;
}

/**
 * @brief Read - blocking read waits for debounced key event
 */
static ssize_t key_read(struct file* file, char __user* buf, size_t count, loff_t* ppos) {
    struct key_debounce_dev* dev = file->private_data;
    int key_value;
    unsigned long flags;

    if (count < sizeof(int)) {
        pr_err("key_read: buffer too small\n");
        return -EINVAL;
    }

    /* Wait for event */
    if (wait_event_interruptible(dev->waitq, dev->event_ready)) {
        return -ERESTARTSYS;
    }

    spin_lock_irqsave(&dev->lock, flags);

    /* Get key value and reset event flag */
    key_value = dev->key_value;
    dev->event_ready = false;

    spin_unlock_irqrestore(&dev->lock, flags);

    if (copy_to_user(buf, &key_value, sizeof(key_value))) {
        pr_err("key_read: copy_to_user failed\n");
        return -EFAULT;
    }

    pr_debug("key_read: returned key value %d\n", key_value);
    return sizeof(key_value);
}

/**
 * @brief Poll - support for non-blocking I/O
 */
static __poll_t key_poll(struct file* file, struct poll_table_struct* pt) {
    struct key_debounce_dev* dev = file->private_data;
    __poll_t mask = 0;

    poll_wait(file, &dev->waitq, pt);

    if (dev->event_ready) {
        mask = EPOLLIN | EPOLLRDNORM;
    }

    return mask;
}

/**
 * @brief Probe function - called when device is matched
 */
static int key_probe(struct platform_device* pdev) {
    int ret;

    pr_info("key_probe: probing device\n");

    /* Allocate device structure */
    key_dev = kzalloc(sizeof(*key_dev), GFP_KERNEL);
    if (!key_dev) {
        pr_err("key_probe: failed to allocate memory\n");
        return -ENOMEM;
    }

    /* Initialize spinlock */
    spin_lock_init(&key_dev->lock);

    /* Initialize wait queue */
    init_waitqueue_head(&key_dev->waitq);

    /* Initialize statistics */
    atomic_set(&key_dev->irq_count, 0);
    atomic_set(&key_dev->event_count, 0);
    atomic_set(&key_dev->debounce_skipped, 0);

    /* Initialize GPIO hardware */
    ret = key_hw_init(&pdev->dev, &key_dev->gpio);
    if (ret) {
        pr_err("key_probe: key_hw_init failed\n");
        goto err_free_dev;
    }

    /* Get initial GPIO state */
    key_dev->last_gpio_state = key_get_state(key_dev->gpio);

    /* Initialize work queue */
    INIT_WORK(&key_dev->work, key_work_handler);

    /* Request interrupt (both edges) */
    ret = key_hw_request_irq(&pdev->dev, key_dev->gpio, key_irq_handler,
                             IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING, DEVICE_NAME, key_dev);
    if (ret < 0) {
        pr_err("key_probe: key_hw_request_irq failed\n");
        goto err_hw_deinit;
    }
    key_dev->irq = ret;

    /* Allocate device number */
    ret = alloc_chrdev_region(&key_dev->devid, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        pr_err("key_probe: alloc_chrdev_region failed\n");
        goto err_hw_deinit;
    }
    key_dev->major = MAJOR(key_dev->devid);

    /* Initialize cdev */
    cdev_init(&key_dev->cdev, &key_fops);
    ret = cdev_add(&key_dev->cdev, key_dev->devid, 1);
    if (ret) {
        pr_err("key_probe: cdev_add failed\n");
        goto err_unregister_chrdev;
    }

    /* Create class */
    key_dev->class = class_create(CLASS_NAME);
    if (IS_ERR(key_dev->class)) {
        pr_err("key_probe: class_create failed\n");
        ret = PTR_ERR(key_dev->class);
        goto err_cdev_del;
    }

    /* Create device */
    key_dev->device = device_create(key_dev->class, &pdev->dev, key_dev->devid, NULL, DEVICE_NAME);
    if (IS_ERR(key_dev->device)) {
        pr_err("key_probe: device_create failed\n");
        ret = PTR_ERR(key_dev->device);
        goto err_class_destroy;
    }

    platform_set_drvdata(pdev, key_dev);
    pr_info("key_probe: device registered as %s (major %d, IRQ %d)\n", DEVICE_NAME, key_dev->major,
            key_dev->irq);

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

/**
 * @brief Remove function - called when device is removed
 */
static void key_remove(struct platform_device* pdev) {
    struct key_debounce_dev* dev = platform_get_drvdata(pdev);

    pr_info("key_remove: removing device\n");

    if (dev) {
        /* Cancel any pending work */
        cancel_work_sync(&dev->work);

        device_destroy(dev->class, dev->devid);
        class_destroy(dev->class);
        cdev_del(&dev->cdev);
        unregister_chrdev_region(dev->devid, 1);
        key_hw_deinit(dev->gpio);

        /* Print statistics */
        pr_info("key_remove: statistics - IRQs: %d, events: %d, skipped: %d\n",
                atomic_read(&dev->irq_count), atomic_read(&dev->event_count),
                atomic_read(&dev->debounce_skipped));

        kfree(dev);
    }

    pr_info("key_remove: device removed\n");
}

/* Device tree match table */
static const struct of_device_id key_of_match[] = {{.compatible = DRIVER_NAME}, {/* sentinel */}};
MODULE_DEVICE_TABLE(of, key_of_match);

/* Platform driver structure */
static struct platform_driver key_platform_driver = {
    .probe = key_probe,
    .remove = key_remove,
    .driver =
        {
            .name = DRIVER_NAME,
            .of_match_table = key_of_match,
        },
};

module_platform_driver(key_platform_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Tutorial 18: Debounced Key Driver (Interrupt + Work Queue)");
MODULE_VERSION("0.1");
