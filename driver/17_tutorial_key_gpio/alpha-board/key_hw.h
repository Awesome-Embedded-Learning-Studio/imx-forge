/**
 * @file key_hw.h
 * @brief Key hardware control interface
 */

#pragma once

#include <linux/gpio/consumer.h>
#include <linux/types.h>

/**
 * @brief Initialize key GPIO (get from device tree, set as input)
 * @param dev Device with device_tree node
 * @param gpio Output pointer to gpio_desc
 * @return 0 on success, negative error code on failure
 */
int key_hw_init(struct device *dev, struct gpio_desc **gpio);

/**
 * @brief Cleanup key hardware resources
 * @param gpio GPIO descriptor to cleanup
 */
void key_hw_deinit(struct gpio_desc *gpio);

/**
 * @brief Get current key state
 * @param gpio GPIO descriptor
 * @return 0 = pressed, 1 = released
 */
int key_get_state(struct gpio_desc *gpio);
