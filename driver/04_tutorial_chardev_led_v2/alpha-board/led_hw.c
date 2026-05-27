/**
 * @file led_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief LED hardware control implementation
 * @version 0.1
 * @date 2026-04-18
 */

#include "led_hw.h"
#include "asm/io.h"
#include "led_reg.h"
#include "linux/printk.h"
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static void __iomem* IMX6U_CCM_CCGR1 = NULL;
static void __iomem* SW_MUX_GPIO1_IO03 = NULL;
static void __iomem* SW_PAD_GPIO1_IO03 = NULL;
static void __iomem* GPIO1_DR = NULL;
static void __iomem* GPIO1_GDIR = NULL;

static const size_t kRegSize = sizeof(u32);

static void pr_bin_u32(u32 val) {
    char buf[33];
    for (int i = 0; i < 32; i++) {
        buf[i] = (val & (1u << (31 - i))) ? '1' : '0';
    }
    buf[32] = '\0';
    pr_cont("%s", buf);
}

static void ioremapping_registers(void) {
#define IOREMAP(BASE_ADDR) ioremap(BASE_ADDR, kRegSize)
    IMX6U_CCM_CCGR1 = IOREMAP(kCCM_CCGR1_BASE);
    SW_MUX_GPIO1_IO03 = IOREMAP(kSW_MUX_GPIO1_IO03_BASE);
    SW_PAD_GPIO1_IO03 = IOREMAP(kSW_PAD_GPIO1_IO03_BASE);
    GPIO1_DR = IOREMAP(kGPIO1_DR_BASE);
    GPIO1_GDIR = IOREMAP(kGPIO1_GDIR_BASE);
#undef IOREMAP

    pr_info("IMX6U_CCM_CCGR1    = 0x%p (phys: 0x%x)\n", IMX6U_CCM_CCGR1, kCCM_CCGR1_BASE);
    pr_info("SW_MUX_GPIO1_IO03  = 0x%p (phys: 0x%x)\n", SW_MUX_GPIO1_IO03, kSW_MUX_GPIO1_IO03_BASE);
    pr_info("SW_PAD_GPIO1_IO03  = 0x%p (phys: 0x%x)\n", SW_PAD_GPIO1_IO03, kSW_PAD_GPIO1_IO03_BASE);
    pr_info("GPIO1_DR           = 0x%p (phys: 0x%x)\n", GPIO1_DR, kGPIO1_DR_BASE);
    pr_info("GPIO1_GDIR         = 0x%p (phys: 0x%x)\n", GPIO1_GDIR, kGPIO1_GDIR_BASE);
}

static void enable_gpio_clock(void) {
    u32 clock_settings = readl(IMX6U_CCM_CCGR1);
    pr_info("CCGR1 raw value: 0x%08x\n Bits: ", clock_settings);
    pr_info("\n");
    pr_bin_u32(clock_settings);

    clock_settings &= ~(0b11 << 26);
    clock_settings |= 0b11 << 26;

    pr_info("CCGR1 new raw value: 0x%08x \nBits: ", clock_settings);
    pr_bin_u32(clock_settings);
    pr_info("\n");
    writel(clock_settings, IMX6U_CCM_CCGR1);
}

static void gpio_func_init(void) {
    const u32 kGPIO_MUX_SETTINGS = 0b101;
    pr_info("Setting SW_MUX_GPIO1_IO03 = 0x%x\n", kGPIO_MUX_SETTINGS);
    writel(kGPIO_MUX_SETTINGS, SW_MUX_GPIO1_IO03);

    const u32 kGPIO_PAD_SETTINGS = 0x10B0;
    writel(kGPIO_PAD_SETTINGS, SW_PAD_GPIO1_IO03);

    const u32 kGPIO_DR_OUTPUT = (1 << 3);
    u32 gpio_direction = readl(GPIO1_GDIR);
    gpio_direction &= ~kGPIO_DR_OUTPUT;
    gpio_direction |= kGPIO_DR_OUTPUT;
    writel(gpio_direction, GPIO1_GDIR);
    pr_info("GPIO1_GDIR set to 0x%08x\n", gpio_direction);

    u32 gpio_val = readl(GPIO1_DR);
    gpio_val |= (1 << 3);
    writel(gpio_val, GPIO1_DR);
    pr_info("GPIO1_DR init set to 0x%08x (LED OFF)\n", gpio_val);
}

void led_hw_init(void) {
    pr_info("Step 0: Request MMU Mappings by ioremap\n");
    ioremapping_registers();

    pr_info("Step 1: GPIO Enable Clock\n");
    enable_gpio_clock();

    pr_info("Step 2: GPIO Functional Settings\n");
    gpio_func_init();

    pr_info("LED Init OK!\n");
}

void led_hw_deinit(void) {
    pr_info("Deinit the LED Hardware\n");
    iounmap(IMX6U_CCM_CCGR1);
    iounmap(SW_MUX_GPIO1_IO03);
    iounmap(SW_PAD_GPIO1_IO03);
    iounmap(GPIO1_DR);
    iounmap(GPIO1_GDIR);
}

void led_set_status(bool status) {
    const u32 led_bits = (1 << 3);
    u32 gpio_val = readl(GPIO1_DR);
    pr_info("led_set_status: status=%d, GPIO1_DR before=0x%08x\n", status, gpio_val);
    if (status) {
        gpio_val &= ~led_bits;
    } else {
        gpio_val |= led_bits;
    }
    writel(gpio_val, GPIO1_DR);
    pr_info("led_set_status: GPIO1_DR after=0x%08x, bit3=%d\n", gpio_val, !status);
}

bool led_get_status(void) {
    u32 gpio_val = readl(GPIO1_DR);
    return (gpio_val & (1 << 3)) == 0;
}