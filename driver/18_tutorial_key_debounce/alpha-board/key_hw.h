/**
 * @file key_hw.h
 * @brief Key hardware control interface with interrupt support
 */

#pragma once

#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
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

/**
 * @brief Request interrupt for the key GPIO
 * @param dev Device for devm_* allocation
 * @param gpio GPIO descriptor
 * @param handler Interrupt handler function
 * @param flags Interrupt flags (IRQF_TRIGGER_*)
 * @param name Interrupt name
 * @param dev_id Device ID passed to handler
 * @return IRQ number on success, negative error code on failure
 */
int key_hw_request_irq(struct device *dev, struct gpio_desc *gpio,
                       irq_handler_t handler, unsigned long flags,
                       const char *name, void *dev_id);

/**
 * @brief Free the key interrupt
 * @param gpio GPIO descriptor
 * @param dev_id Device ID used during request
 */
void key_hw_free_irq(struct gpio_desc *gpio, void *dev_id);
