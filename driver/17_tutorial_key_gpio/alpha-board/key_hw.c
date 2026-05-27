/**
 * @file key_hw.c
 * @author Charliechen114514
 * @brief Key hardware control implementation
 * @version 0.1
 * @date 2026-05-27
 */

#include "key_hw.h"
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/printk.h>

int key_hw_init(struct device *dev, struct gpio_desc **gpio)
{
    struct gpio_desc *gpiod;

    if (!dev || !gpio) {
        pr_err("key_hw_init: invalid parameters\n");
        return -EINVAL;
    }

    gpiod = gpiod_get(dev, NULL, GPIOD_IN);
    if (IS_ERR(gpiod)) {
        pr_err("key_hw_init: failed to get GPIO: %ld\n", PTR_ERR(gpiod));
        return PTR_ERR(gpiod);
    }

    *gpio = gpiod;
    pr_info("key_hw_init: GPIO initialized successfully\n");

    return 0;
}

void key_hw_deinit(struct gpio_desc *gpio)
{
    if (gpio) {
        gpiod_put(gpio);
        pr_info("key_hw_deinit: GPIO released\n");
    }
}

int key_get_state(struct gpio_desc *gpio)
{
    int val;

    if (!gpio) {
        pr_err("key_get_state: invalid gpio\n");
        return -EINVAL;
    }

    val = gpiod_get_value(gpio);
    return !val;  /* Descriptor GPIO returns logical value; keep 0=pressed, 1=released. */
}
