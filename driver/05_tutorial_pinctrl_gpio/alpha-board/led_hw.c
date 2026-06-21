/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control using Device Tree + gpiod descriptor API
 * @version 0.3
 * @date 2026-06-20
 *
 * @note The old of_get_named_gpio() + raw gpio number API was removed from
 *       mainline (linux/of_gpio.h is gone). This now uses the gpiod descriptor
 *       API: fwnode_gpiod_get_index() takes the DT node's fwnode, and gpiod
 *       honours the GPIO_ACTIVE_LOW flag from the device tree for us, so the
 *       manual !-inversion the raw API needed is gone. linux-imx still ships
 *       of_gpio.h, but the descriptor API works on both trees.
 */

#include "led_hw.h"
#include <asm/io.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/printk.h>

/* LED hardware handle */
struct led_handle {
    struct gpio_desc* gpio_desc;      /* descriptor from gpiod, replaces the raw number */
    struct device_node* device_tree_node;
};

static struct led_handle led;

static const char* kIMX_AES_LED = "/imx_aes_led";
/* gpiod consumer id: it appends "-gpios"/"-gpio", so "led" matches the DT "led-gpio" property */
static const char* kIMX_AES_LED_CON_ID = "led";

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

    /* 4. 拿 GPIO 描述符。GPIOD_OUT_LOW 同时设方向 + 初始值（逻辑低 = 灭）。
     *    gpiod 会自动按设备树里的 GPIO_ACTIVE_LOW 处理极性，所以这里给的是"逻辑值"，
     *    不用再像老 number API 那样手动取反。 */
    /*
     * ⚠️ 下面注释掉的是老写法（raw GPIO number API），只有 linux-imx 那棵树能编——
     * mainline 早已删除 linux/of_gpio.h 头文件和 of_get_named_gpio() 函数，原样抄过去
     * 会报 "linux/of_gpio.h: No such file or directory"。保留作对照，新代码改用 gpiod：
     *
     *   led.gpio_sub_sys_nr = of_get_named_gpio(led.device_tree_node, "led-gpio", 0);
     *   if (led.gpio_sub_sys_nr < 0) {
     *       pr_err("Can not parse to get the gpio nr");
     *       return -EINVAL;
     *   }
     *   gpio_direction_output(led.gpio_sub_sys_nr, 1);   // raw 高 = 灭
     */
    led.gpio_desc = fwnode_gpiod_get_index(of_fwnode_handle(led.device_tree_node),
                                           kIMX_AES_LED_CON_ID, 0, GPIOD_OUT_LOW,
                                           "imx-aes-led");
    if (IS_ERR(led.gpio_desc)) {
        pr_err("Can not get the led gpio descriptor: %ld\n", PTR_ERR(led.gpio_desc));
        led.gpio_desc = NULL;
        return -EINVAL;
    }
    pr_info("Get the led gpio descriptor\n");

    pr_info("LED Hardware init finished!\n");
    return 0;
}

void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.gpio_desc) {
        gpiod_put(led.gpio_desc);
        led.gpio_desc = NULL;
    }

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}

void led_set_status(bool status) {
    /* gpiod 按 DT 极性解释逻辑值：status=true → 逻辑高 → 物理拉低 → 灯亮。
     * 老代码 gpio_set_value(nr, !status) 是手动取反，这里不用了。 */
    gpiod_set_value(led.gpio_desc, status);
}

bool led_get_status(void) {
    /* gpiod_get_value 返回的就是逻辑值（亮=1），无需取反。 */
    return gpiod_get_value(led.gpio_desc);
}
