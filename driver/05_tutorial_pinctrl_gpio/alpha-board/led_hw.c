/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control using Device Tree (mainline Linux API style)
 * @version 0.2
 * @date 2026-04-27
 */

#include "led_hw.h"
#include "linux/of_gpio.h"
#include <asm/io.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/printk.h>

/* LED hardware register mapping structure */
struct led_handle {
    int gpio_sub_sys_nr;
    struct device_node* device_tree_node;
};

static struct led_handle led;

static const char* kIMX_AES_LED = "/imx_aes_led";
static const char* kIMX_AES_LED_NAME = "led-gpio";

int led_hw_init(void) {
    /* Get the struct of in the device tree */
    led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
    if (led.device_tree_node == NULL) {
        pr_err("dtsled node can not found!\n");
        return -EINVAL;
    }
    pr_info("dtsled node has been found!\n");

    /* 2. 获取 compatible 属性 */
    struct property* proper = of_find_property(led.device_tree_node, "compatible", NULL);
    if (proper == NULL) {
        pr_err("compatible property find failed\n");
    } else {
        pr_info("compatible = %s\n", (char*)proper->value);
    }

    /* 3. 获取 status 属性 */
    const char* str;
    if (of_property_read_string(led.device_tree_node, "status", &str) < 0) {
        pr_err("status read failed!\n");
    } else {
        pr_info("status = %s\n", str);
    }

    led.gpio_sub_sys_nr = of_get_named_gpio(led.device_tree_node, kIMX_AES_LED_NAME, 0);
    if (led.gpio_sub_sys_nr < 0) {
        pr_err("Can not parse to get the gpio nr");
        return -EINVAL;
    } else {
        pr_info("Get the gpio handle: %d", led.gpio_sub_sys_nr);
    }

    // Set As val: output mode
    gpio_direction_output(led.gpio_sub_sys_nr, 1);

    pr_info("LED Hardware init finished!\n");
    return 0;
}

void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}

void led_set_status(bool status) {
    // set the value, now only in one statement!
    gpio_set_value(led.gpio_sub_sys_nr, (int)(!status));
}

bool led_get_status(void) {
    return !gpio_get_value(led.gpio_sub_sys_nr);
}
