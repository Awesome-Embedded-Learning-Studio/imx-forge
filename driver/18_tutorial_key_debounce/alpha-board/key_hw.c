/**
 * @file key_hw.c
 * @author Charliechen114514
 * @brief Key hardware control implementation with interrupt support
 * @version 0.1
 * @date 2026-05-27
 */

#include "key_hw.h"
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/printk.h>

/**
 * @brief Initialize key GPIO from device tree
 */
int key_hw_init(struct device* dev, struct gpio_desc** gpio) {
    struct gpio_desc* gpiod;

    if (!dev || !gpio) {
        pr_err("key_hw_init: invalid parameters\n");
        return -EINVAL;
    }

    /* Get GPIO from device tree (gpios property) */
    gpiod = gpiod_get(dev, NULL, GPIOD_IN);
    if (IS_ERR(gpiod)) {
        pr_err("key_hw_init: failed to get GPIO: %ld\n", PTR_ERR(gpiod));
        return PTR_ERR(gpiod);
    }

    *gpio = gpiod;
    pr_info("key_hw_init: GPIO initialized successfully\n");

    return 0;
}

/**
 * @brief Cleanup key hardware resources
 */
void key_hw_deinit(struct gpio_desc* gpio) {
    if (gpio) {
        gpiod_put(gpio);
        pr_info("key_hw_deinit: GPIO released\n");
    }
}

/**
 * @brief Get current key state
 * @return 0 = pressed, 1 = released
 */
int key_get_state(struct gpio_desc* gpio) {
    int val;

    if (!gpio) {
        pr_err("key_get_state: invalid gpio\n");
        return -EINVAL;
    }

    val = gpiod_get_value(gpio);
    /* Descriptor GPIO returns logical value after GPIO_ACTIVE_LOW.
     * Keep the tutorial's internal state as 0=pressed, 1=released.
     */
    return !val;
}

/**
 * @brief Request interrupt for the key GPIO
 */
int key_hw_request_irq(struct device* dev, struct gpio_desc* gpio, irq_handler_t handler,
                       unsigned long flags, const char* name, void* dev_id) {
    int irq;
    int ret;

    if (!dev || !gpio || !handler) {
        pr_err("key_hw_request_irq: invalid parameters\n");
        return -EINVAL;
    }

    /* Get IRQ number for the GPIO */
    irq = gpiod_to_irq(gpio);
    if (irq < 0) {
        pr_err("key_hw_request_irq: failed to get IRQ: %d\n", irq);
        return irq;
    }

    /* Request the interrupt */
    ret = devm_request_irq(dev, irq, handler, flags, name, dev_id);
    if (ret) {
        pr_err("key_hw_request_irq: failed to request IRQ %d: %d\n", irq, ret);
        return ret;
    }

    pr_info("key_hw_request_irq: IRQ %d requested (%s)\n", irq, name);
    return irq;
}

/**
 * @brief Free the key interrupt (managed, usually no need to call manually)
 */
void key_hw_free_irq(struct gpio_desc* gpio, void* dev_id) {
    int irq;

    if (!gpio) {
        return;
    }

    /* Note: When using devm_request_irq, the IRQ is automatically freed */
    /* This function is provided for manual cleanup if needed */
    irq = gpiod_to_irq(gpio);
    if (irq >= 0) {
        free_irq(irq, dev_id);
        pr_info("key_hw_free_irq: IRQ %d freed\n", irq);
    }
}
