/**
 * @file key_demo.c
 * @author Charliechen114514
 * @brief 按键测试应用程序
 *        支持驱动 17（无消抖）和驱动 18（带消抖）
 * @version 0.1
 * @date 2026-05-27
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>

#define DEV_GPIO       "/dev/imxaes_key"
#define DEV_DEBOUNCE   "/dev/imxaes_key_debounce"

/**
 * @brief 打印使用说明
 */
static void print_usage(const char *prog_name)
{
    printf("用法: %s <模式>\n", prog_name);
    printf("\n");
    printf("模式:\n");
    printf("  gpio      - 测试驱动 17（基础轮询，无消抖）\n");
    printf("              会看到按键抖动现象（按一次可能显示多次）\n");
    printf("\n");
    printf("  debounce  - 测试驱动 18（中断消抖）\n");
    printf("              每次按键只产生一个事件\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s gpio        # 测试无消抖按键\n", prog_name);
    printf("  %s debounce    # 测试带消抖按键\n", prog_name);
    printf("\n");
    printf("按 Ctrl+C 退出\n");
}

/**
 * @brief 获取当前时间戳（纳秒）
 */
static unsigned long long get_timestamp_ns(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (unsigned long long)tv.tv_sec * 1000000000ULL + tv.tv_usec * 1000ULL;
}

/**
 * @brief 监控按键事件
 */
static int monitor_keys(const char *dev_path, const char *mode_name)
{
    int fd;
    int key_value;
    unsigned long long timestamp;
    int count = 0;

    /* 打开设备 */
    fd = open(dev_path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "错误: 无法打开设备 %s: %s\n", dev_path, strerror(errno));
        fprintf(stderr, "请确保驱动已加载 (insmod)\n");
        return -1;
    }

    printf("正在监控按键事件 (%s 模式)\n", mode_name);
    printf("设备: %s\n", dev_path);
    printf("按 Ctrl+C 退出\n");
    printf("----------------------------------------\n");

    /* 循环读取按键事件 */
    while (1) {
        ssize_t bytes = read(fd, &key_value, sizeof(key_value));

        if (bytes == sizeof(key_value)) {
            timestamp = get_timestamp_ns();
            count++;

            if (key_value) {
                printf("[%06d] [%llu ns] 按键: 按下\n", count, timestamp);
            } else {
                printf("[%06d] [%llu ns] 按键: 释放\n", count, timestamp);
            }
        } else if (bytes < 0) {
            if (errno == EINTR) {
                /* 被信号中断，继续 */
                continue;
            }
            fprintf(stderr, "错误: 读取失败: %s\n", strerror(errno));
            break;
        }
    }

    close(fd);
    return 0;
}

int main(int argc, char *argv[])
{
    const char *dev_path;
    const char *mode_name;

    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    /* 解析命令行参数 */
    if (strcmp(argv[1], "gpio") == 0) {
        dev_path = DEV_GPIO;
        mode_name = "GPIO轮询（无消抖）";
    } else if (strcmp(argv[1], "debounce") == 0) {
        dev_path = DEV_DEBOUNCE;
        mode_name = "中断消抖（20ms）";
    } else if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        print_usage(argv[0]);
        return 0;
    } else {
        fprintf(stderr, "错误: 未知模式 '%s'\n\n", argv[1]);
        print_usage(argv[0]);
        return 1;
    }

    /* 监控按键 */
    return monitor_keys(dev_path, mode_name);
}
