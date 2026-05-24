/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control using GPIO descriptor API
 * @version 1.0
 * @date 2026-05-24
 */

#include "led_hw.h"
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/printk.h>

int led_hw_init(struct device* dev, struct led_hw_ctx* ctx) {
    if (!dev || !ctx) {
        pr_err("Invalid parameters\n");
        return -EINVAL;
    }

    /* Get GPIO descriptor from device tree ("led-gpio" property) */
    ctx->gpio = devm_gpiod_get(dev, "led", GPIOD_OUT_LOW);
    if (IS_ERR(ctx->gpio)) {
        int err = PTR_ERR(ctx->gpio);
        dev_err_probe(dev, err, "Failed to get led GPIO\n");
        return err;
    }

    dev_info(dev, "LED hardware initialized\n");
    return 0;
}

void led_hw_deinit(struct led_hw_ctx* ctx) {
    if (!ctx) {
        return;
    }

    /* GPIO is managed by devm_, no need to free explicitly */
    pr_info("LED hardware deinitialized\n");
}

void led_set_status(struct led_hw_ctx* ctx, bool status) {
    if (!ctx || !ctx->gpio) {
        return;
    }

    /* GPIOD API handles active_low automatically */
    gpiod_set_value(ctx->gpio, status ? 1 : 0);
}

bool led_get_status(struct led_hw_ctx* ctx) {
    if (!ctx || !ctx->gpio) {
        return false;
    }

    return gpiod_get_value(ctx->gpio) != 0;
}
