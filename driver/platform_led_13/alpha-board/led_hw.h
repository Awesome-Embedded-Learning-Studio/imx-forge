/**
 * @file led_hw.h
 * @brief LED hardware control interface for platform driver
 */

#pragma once

#include <linux/types.h>

struct device;
struct gpio_desc;

/**
 * @brief LED hardware context
 */
struct led_hw_ctx {
    struct gpio_desc* gpio;
};

/**
 * @brief Initialize LED hardware from platform device
 * @param dev Device from platform_device
 * @param ctx Context to initialize
 * @return 0 on success, negative errno on failure
 */
int led_hw_init(struct device* dev, struct led_hw_ctx* ctx);

/**
 * @brief Deinitialize LED hardware
 * @param ctx LED context
 */
void led_hw_deinit(struct led_hw_ctx* ctx);

/**
 * @brief Set LED on/off status
 * @param ctx LED context
 * @param status true = LED on, false = LED off
 */
void led_set_status(struct led_hw_ctx* ctx, bool status);

/**
 * @brief Get LED status
 * @param ctx LED context
 * @return true: led is currently on, false: led is off
 */
bool led_get_status(struct led_hw_ctx* ctx);
