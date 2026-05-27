/**
 * @file 19_tutorial_key_input_driver.c
 * @author Charliechen114514
 * @brief Tutorial 19: Input Subsystem Key Driver
 *        Demonstrates the standard Linux Input Subsystem approach for key drivers.
 *        This is the recommended way to implement input device drivers in Linux.
 * @version 0.1
 * @date 2026-05-27
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/input.h>
#include <linux/slab.h>
#include <linux/interrupt.h>
#include <linux/workqueue.h>
#include <linux/of.h>
#include <linux/delay.h>
#include <linux/spinlock.h>

#include "key_hw.h"

#define DRIVER_NAME "imxaes-input-key"
#define DEBOUNCE_MS 20

/* Device structure */
struct input_key_dev {
    struct gpio_desc *gpio;
    struct input_dev *input_dev;
    struct delayed_work debounce_work;
    spinlock_t lock;
    int last_state;
};

/* Function prototypes */
static void debounce_work_handler(struct work_struct *work);
static irqreturn_t input_key_irq_handler(int irq, void *dev_id);

/**
 * @brief Delayed work handler - debounce and report event
 */
static void debounce_work_handler(struct work_struct *work)
{
    struct delayed_work *dwork = to_delayed_work(work);
    struct input_key_dev *dev = container_of(dwork, struct input_key_dev, debounce_work);
    int current_state;
    unsigned long flags;

    /* Read logical GPIO state after debounce delay */
    current_state = key_hw_get_raw_state(dev->gpio);

    spin_lock_irqsave(&dev->lock, flags);

    /* Only report if state changed from last reported state */
    if (current_state != dev->last_state) {
        dev->last_state = current_state;

        /* gpiod_get_value() already applies GPIO_ACTIVE_LOW. */
        input_report_key(dev->input_dev, KEY_ENTER, current_state);
        input_sync(dev->input_dev);

        pr_debug("input_key_work: key %s\n", current_state ? "pressed" : "released");
    }

    spin_unlock_irqrestore(&dev->lock, flags);
}

/**
 * @brief Interrupt handler - schedules/reschedules delayed work
 */
static irqreturn_t input_key_irq_handler(int irq, void *dev_id)
{
    struct input_key_dev *dev = dev_id;

    /* Reschedule the delayed work (cancels any pending and restarts timer) */
    mod_delayed_work(system_wq, &dev->debounce_work, msecs_to_jiffies(DEBOUNCE_MS));

    return IRQ_HANDLED;
}

/**
 * @brief Probe function - called when device is matched
 */
static int input_key_probe(struct platform_device *pdev)
{
    struct input_key_dev *dev;
    int ret;

    pr_info("input_key_probe: probing device\n");

    /* Allocate device structure */
    dev = kzalloc(sizeof(*dev), GFP_KERNEL);
    if (!dev) {
        pr_err("input_key_probe: failed to allocate memory\n");
        return -ENOMEM;
    }

    /* Initialize spinlock */
    spin_lock_init(&dev->lock);

    /* Initialize GPIO hardware */
    ret = key_hw_init(&pdev->dev, &dev->gpio);
    if (ret) {
        pr_err("input_key_probe: key_hw_init failed\n");
        goto err_free_dev;
    }

    /* Get initial logical GPIO state */
    dev->last_state = key_hw_get_raw_state(dev->gpio);

    /* Allocate input device */
    dev->input_dev = input_allocate_device();
    if (!dev->input_dev) {
        pr_err("input_key_probe: failed to allocate input device\n");
        ret = -ENOMEM;
        goto err_hw_deinit;
    }

    /* Configure input device */
    dev->input_dev->name = "imxaes-key";
    dev->input_dev->phys = "imxaes-key/input0";
    dev->input_dev->id.bustype = BUS_HOST;
    dev->input_dev->id.vendor = 0x0001;
    dev->input_dev->id.product = 0x0001;
    dev->input_dev->id.version = 0x0100;

    /* Set EV_KEY capability */
    set_bit(EV_KEY, dev->input_dev->evbit);
    set_bit(KEY_ENTER, dev->input_dev->keybit);

    /* Register input device */
    ret = input_register_device(dev->input_dev);
    if (ret) {
        pr_err("input_key_probe: failed to register input device: %d\n", ret);
        goto err_free_input_dev;
    }

    /* Initialize delayed work */
    INIT_DELAYED_WORK(&dev->debounce_work, debounce_work_handler);

    /* Request interrupt (both edges) */
    ret = key_hw_request_irq(&pdev->dev, dev->gpio, input_key_irq_handler,
                             IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
                             "imxaes-input-key", dev);
    if (ret < 0) {
        pr_err("input_key_probe: key_hw_request_irq failed\n");
        goto err_free_input_dev;
    }

    platform_set_drvdata(pdev, dev);

    pr_info("input_key_probe: device registered (IRQ %d)\n", ret);
    pr_info("input_key_probe: input device: %s\n", dev->input_dev->name);

    return 0;

err_free_input_dev:
    input_free_device(dev->input_dev);
err_hw_deinit:
    key_hw_deinit(dev->gpio);
err_free_dev:
    kfree(dev);
    return ret;
}

/**
 * @brief Remove function - called when device is removed
 */
static void input_key_remove(struct platform_device *pdev)
{
    struct input_key_dev *dev = platform_get_drvdata(pdev);

    pr_info("input_key_remove: removing device\n");

    if (dev) {
        /* Cancel delayed work */
        cancel_delayed_work_sync(&dev->debounce_work);

        /* Unregister input device */
        input_unregister_device(dev->input_dev);

        /* Release GPIO hardware */
        key_hw_deinit(dev->gpio);

        /* Free device structure */
        kfree(dev);
    }

    pr_info("input_key_remove: device removed\n");
}

/* Device tree match table */
static const struct of_device_id input_key_of_match[] = {
    { .compatible = DRIVER_NAME },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, input_key_of_match);

/* Platform driver structure */
static struct platform_driver input_key_platform_driver = {
    .probe = input_key_probe,
    .remove = input_key_remove,
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = input_key_of_match,
    },
};

module_platform_driver(input_key_platform_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Tutorial 19: Input Subsystem Key Driver");
MODULE_VERSION("0.1");
