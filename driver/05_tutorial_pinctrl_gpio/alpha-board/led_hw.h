/**
 * @file led_hw.h
 * @brief LED hardware control interface
 */

#pragma once

#include <linux/types.h>

/**
 * @brief Initialize LED hardware (clock, GPIO mux/pad, direction)
 * @return 0 on success, negative errno on failure
 */
int led_hw_init(void);

/**
 * @brief Deinit the usage
 * 
 */
void led_hw_deinit(void);

/**
 * @brief Set LED on/off status
 * @param status true = LED on, false = LED off
 */
void led_set_status(bool status);

/**
 * @brief Get LED status
 * 
 * @return true: led is currently on
 * @return false: led is currently false
 */
bool led_get_status(void);

