/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control using Device Tree (mainline Linux API style)
 * @version 0.2
 * @date 2026-04-27
 */

#include "led_hw.h"
#include <asm/io.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/printk.h>

/* LED hardware register mapping structure */
struct led_handle {
    void __iomem* ccm_ccgr1;
    void __iomem* sw_mux_gpio;
    void __iomem* sw_pad_gpio;
    void __iomem* gpio_dr;
    void __iomem* gpio_gdir;
    struct device_node* device_tree_node;
};

static struct led_handle led;

static const char* kIMX_AES_LED = "/imx_aes_led";

static void pr_bin_u32(u32 val) {
    char buf[33];
    for (int i = 0; i < 32; i++) {
        buf[i] = (val & (1u << (31 - i))) ? '1' : '0';
    }
    buf[32] = '\0';
    pr_cont("%s", buf);
}

int led_hw_init(void) {
    u32 regdata[10];
    int ret;
    const char* str;
    struct property* proper;
    u32 val;

    /* Get the struct of in the device tree */
    led.device_tree_node = of_find_node_by_path(kIMX_AES_LED);
    if (led.device_tree_node == NULL) {
        pr_err("dtsled node can not found!\n");
        return -EINVAL;
    }
    pr_info("dtsled node has been found!\n");

    /* 2. 获取 compatible 属性 */
    proper = of_find_property(led.device_tree_node, "compatible", NULL);
    if (proper == NULL) {
        pr_err("compatible property find failed\n");
    } else {
        pr_info("compatible = %s\n", (char*)proper->value);
    }

    /* 3. 获取 status 属性 */
    ret = of_property_read_string(led.device_tree_node, "status", &str);
    if (ret < 0) {
        pr_err("status read failed!\n");
    } else {
        pr_info("status = %s\n", str);
    }

    /* 4. 获取 reg 属性内容 */
    ret = of_property_read_u32_array(led.device_tree_node, "reg", regdata, 10);
    if (ret < 0) {
        pr_err("reg property read failed!\n");
        of_node_put(led.device_tree_node);
        return -EINVAL;
    }

    pr_info("reg data:\n");
    for (int i = 0; i < 10; i++) {
        pr_cont("%#X ", regdata[i]);
    }
    pr_cont("\n");

    /* 5. 使用 of_iomap 进行寄存器地址映射 */
    led.ccm_ccgr1 = of_iomap(led.device_tree_node, 0);
    led.sw_mux_gpio = of_iomap(led.device_tree_node, 1);
    led.sw_pad_gpio = of_iomap(led.device_tree_node, 2);
    led.gpio_dr = of_iomap(led.device_tree_node, 3);
    led.gpio_gdir = of_iomap(led.device_tree_node, 4);

    if (!led.ccm_ccgr1 || !led.sw_mux_gpio || !led.sw_pad_gpio || !led.gpio_dr || !led.gpio_gdir) {
        pr_err("ioremap failed!\n");
        of_node_put(led.device_tree_node);
        return -ENOMEM;
    }

    pr_info("IMX6U_CCM_CCGR1    = 0x%p\n", led.ccm_ccgr1);
    pr_info("SW_MUX_GPIO1_IO03  = 0x%p\n", led.sw_mux_gpio);
    pr_info("SW_PAD_GPIO1_IO03  = 0x%p\n", led.sw_pad_gpio);
    pr_info("GPIO1_DR           = 0x%p\n", led.gpio_dr);
    pr_info("GPIO1_GDIR         = 0x%p\n", led.gpio_gdir);

    /* 6. 使能GPIO1时钟 */
    val = readl(led.ccm_ccgr1);
    pr_info("CCGR1 raw value: 0x%08x\n Bits: ", val);
    pr_bin_u32(val);
    pr_cont("\n");

    val &= ~(3 << 26); /* 清除以前的设置 */
    val |= (3 << 26);  /* 设置新值 */
    writel(val, led.ccm_ccgr1);

    pr_info("CCGR1 new value: 0x%08x\n Bits: ", val);
    pr_bin_u32(val);
    pr_cont("\n");

    /* 7. 设置GPIO1_IO03复用功能为GPIO */
    writel(5, led.sw_mux_gpio);

    /* 8. 设置GPIO1_IO03电气属性 */
    writel(0x10B0, led.sw_pad_gpio);

    /* 9. 设置GPIO1_IO03为输出功能 */
    val = readl(led.gpio_gdir);
    val &= ~(3 << 3); /* 清除以前的设置 */
    val |= (1 << 3);  /* 设置为输出 */
    writel(val, led.gpio_gdir);
    pr_info("GPIO1_GDIR = 0x%08x\n", val);

    /* 10. 默认关闭LED (高电平) */
    val = readl(led.gpio_dr);
    val |= (1 << 3);
    writel(val, led.gpio_dr);
    pr_info("GPIO1_DR init = 0x%08x (LED OFF)\n", val);

    pr_info("LED Init OK!\n");
    return 0;
}

void led_hw_deinit(void) {
    pr_info("Deinit LED Hardware\n");

    if (led.ccm_ccgr1) {
        iounmap(led.ccm_ccgr1);
        led.ccm_ccgr1 = NULL;
    }
    if (led.sw_mux_gpio) {
        iounmap(led.sw_mux_gpio);
        led.sw_mux_gpio = NULL;
    }
    if (led.sw_pad_gpio) {
        iounmap(led.sw_pad_gpio);
        led.sw_pad_gpio = NULL;
    }
    if (led.gpio_dr) {
        iounmap(led.gpio_dr);
        led.gpio_dr = NULL;
    }
    if (led.gpio_gdir) {
        iounmap(led.gpio_gdir);
        led.gpio_gdir = NULL;
    }

    if (led.device_tree_node) {
        of_node_put(led.device_tree_node);
        led.device_tree_node = NULL;
    }
}

void led_set_status(bool status) {
    u32 val = readl(led.gpio_dr);
    pr_info("led_set_status: status=%d, GPIO1_DR before=0x%08x\n", status, val);

    if (status) {
        val &= ~(1 << 3); /* 低电平点亮 */
    } else {
        val |= (1 << 3); /* 高电平熄灭 */
    }
    writel(val, led.gpio_dr);

    pr_info("led_set_status: GPIO1_DR after=0x%08x\n", val);
}

bool led_get_status(void) {
    u32 val = readl(led.gpio_dr);
    return (val & (1 << 3)) == 0;
}
