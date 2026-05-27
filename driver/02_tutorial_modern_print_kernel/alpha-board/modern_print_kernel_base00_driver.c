#include <linux/printk.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/version.h>

// 统一打印前缀 - 所有 pr_* 宏都会自动添加这个前缀
// 注：如果内核头文件已定义，这里会覆盖它，这是正常的
#ifndef pr_fmt
#define pr_fmt(fmt) "MODERN_PRINT_KERNEL: " fmt
#endif

// 模块参数 - 动态控制调试级别
static int debug_level = 1;
module_param(debug_level, int, 0644);
MODULE_PARM_DESC(debug_level, "Debug level (0=none, 1=info, 2=debug)");

/**
 * demonstrate_kernel_log_levels() - 展示所有8种内核日志级别
 *
 * 此函数演示 Linux 内核中的所有日志级别宏：
 * - pr_emerg (0): 紧急情况，系统不可用
 * - pr_alert (1): 警报，需要立即采取行动
 * - pr_crit (2): 严重条件
 * - pr_err (3): 错误条件
 * - pr_warn (4): 警告条件
 * - pr_notice (5): 正常但重要的条件
 * - pr_info (6): 信息性消息
 * - pr_debug (7): 调试级别消息
 */
static void demonstrate_kernel_log_levels(void)
{
    pr_info("\n");
    pr_info("--- Demonstrating Kernel Log Levels ---\n");

    // Level 0: 紧急情况 - 系统不可用
    pr_emerg("EMERGENCY: System is unusable (level 0)\n");

    // Level 1: 警报 - 需要立即采取行动
    pr_alert("ALERT: Action must be taken immediately (level 1)\n");

    // Level 2: 严重 - 严重条件
    pr_crit("CRITICAL: Critical conditions occurred (level 2)\n");

    // Level 3: 错误 - 错误条件
    pr_err("ERROR: Error condition detected (level 3)\n");

    // Level 4: 警告 - 警告条件
    pr_warn("WARNING: Warning condition (level 4)\n");

    // Level 5: 通知 - 正常但重要
    pr_notice("NOTICE: Normal but significant condition (level 5)\n");

    // Level 6: 信息 - 信息性消息
    pr_info("INFO: Informational message (level 6)\n");

    // Level 7: 调试 - 调试级别消息
    pr_debug("DEBUG: Debug-level message (level 7)\n");

    pr_info("--- End of Log Level Demonstration ---\n");
    pr_info("\n");
}

/**
 * demonstrate_advanced_printk_features() - 展示高级 printk 功能
 *
 * 此函数演示内核中的高级打印功能：
 * - *_once(): 一次性打印，即使多次调用也只输出一次
 * - pr_cont(): 连续打印，不添加前缀和时间戳
 * - 条件打印: 基于模块参数的动态控制
 */
static void demonstrate_advanced_printk_features(void)
{
    pr_info("--- Advanced printk Features ---\n");

    // 一次性打印 - 即使在循环中也只打印一次
    pr_info_once("This INFO_ONCE message will only appear once\n");
    pr_warn_once("This WARN_ONCE message will only appear once\n");
    pr_err_once("This ERR_ONCE message will only appear once\n");

    // 多行连续打印 - 不添加时间戳和前缀
    pr_info("Multi-line message example:\n");
    pr_cont("  - Line 1: Continued line without prefix\n");
    pr_cont("  - Line 2: Continued line without prefix\n");
    pr_cont("  - Line 3: Continued line without prefix\n");

    pr_info("--- End of Advanced Features ---\n");
    pr_info("\n");
}

/**
 * demonstrate_conditional_printing() - 展示条件打印
 *
 * 此函数演示如何根据模块参数动态控制打印输出
 */
static void demonstrate_conditional_printing(void)
{
    // 条件打印示例
    if (debug_level >= 1) {
        pr_info("Debug level >= 1: Basic information enabled\n");
    }

    if (debug_level >= 2) {
        pr_debug("Debug level >= 2: Detailed debug information\n");
        pr_debug("Module author: Charliechen114514\n");
        pr_debug("Module version: 1.0\n");
        pr_debug("Kernel version: %d.%d.%d\n", LINUX_VERSION_CODE >> 16,
                 (LINUX_VERSION_CODE >> 8) & 0xff, LINUX_VERSION_CODE & 0xff);
    }
}

/**
 * run_all_printk_demonstrations() - 运行所有打印演示
 *
 * 此函数调用所有演示函数，展示完整的内核打印功能
 */
static void run_all_printk_demonstrations(void)
{
    // Much Thanks to the 《Linux_Kernel_Programming》 I know this
    // in this book :)
    pr_debug("This is a Debug Message (only visible with DEBUG enabled)\n");

    // 展示所有日志级别
    demonstrate_kernel_log_levels();

    // 展示高级功能
    demonstrate_advanced_printk_features();

    // 展示条件打印
    demonstrate_conditional_printing();
}

// 模块初始化
static int __init modern_print_kernel_base00_init(void) {
    pr_info("=== Modern Kernel Print Usage Demo ===\n");
    pr_info("Module loading with debug level: %d\n", debug_level);
    pr_info("Demonstrating modern printk features in Linux kernel\n");

    // 运行所有打印演示
    run_all_printk_demonstrations();

    pr_info("========================\n");
    pr_info("Module initialized successfully!\n");
    pr_info("Use 'dmesg | grep MODERN_PRINT_KERNEL' to see all messages\n");
    pr_info("Use 'echo 8 > /proc/sys/kernel/printk' to see DEBUG messages\n");
    pr_info("========================\n");

    return 0;
}

// 模块退出
static void __exit modern_print_kernel_base00_exit(void) {
    pr_info("=== Modern Print Kernel module unloaded ===\n");
    pr_info("========================\n");
}

module_init(modern_print_kernel_base00_init);
module_exit(modern_print_kernel_base00_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Charliechen114514");
MODULE_DESCRIPTION("Modern Linux Kernel Print Usage Demonstration");
MODULE_VERSION("1.0");
