/**
 * @file input_key_demo.c
 * @author Charliechen114514
 * @brief Input 子系统按键测试应用程序
 *        使用 evdev API 读取 input 事件
 * @version 0.1
 * @date 2026-05-27
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <linux/input.h>

#define EVENT_DEV_NAME "imxaes-key"

/**
 * @brief 打印使用说明
 */
static void print_usage(const char *prog_name)
{
    printf("用法: %s [选项]\n", prog_name);
    printf("\n");
    printf("选项:\n");
    printf("  -d <设备>    指定 input 设备路径 (默认: 自动查找)\n");
    printf("  -l          列出所有 input 设备\n");
    printf("  -h          显示帮助信息\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s              # 自动查找 imxaes-key 设备\n", prog_name);
    printf("  %s -d /dev/input/event0  # 指定设备\n", prog_name);
    printf("  %s -l          # 列出所有 input 设备\n", prog_name);
    printf("\n");
    printf("按 Ctrl+C 退出\n");
}

/**
 * @brief 列出所有 input 设备
 */
static int list_input_devices(void)
{
    char dev_path[64];
    char dev_name[256];
    int fd, i;

    printf("可用的 input 设备:\n");
    printf("----------------------------------------\n");

    for (i = 0; i < 32; i++) {
        snprintf(dev_path, sizeof(dev_path), "/dev/input/event%d", i);

        fd = open(dev_path, O_RDONLY);
        if (fd < 0) {
            continue;
        }

        if (ioctl(fd, EVIOCGNAME(sizeof(dev_name)), dev_name) >= 0) {
            printf("%s\t%s\n", dev_path, dev_name);
        }

        close(fd);
    }

    return 0;
}

/**
 * @brief 查找 imxaes-key 设备
 */
static int find_input_device(char *path, size_t path_size)
{
    char dev_path[64];
    char dev_name[256];
    int fd, i;

    for (i = 0; i < 32; i++) {
        snprintf(dev_path, sizeof(dev_path), "/dev/input/event%d", i);

        fd = open(dev_path, O_RDONLY);
        if (fd < 0) {
            continue;
        }

        if (ioctl(fd, EVIOCGNAME(sizeof(dev_name)), dev_name) >= 0) {
            if (strcmp(dev_name, EVENT_DEV_NAME) == 0) {
                snprintf(path, path_size, "%s", dev_path);
                close(fd);
                return 0;
            }
        }

        close(fd);
    }

    return -1;
}

/**
 * @brief 监控 input 事件
 */
static int monitor_input_events(const char *dev_path)
{
    int fd;
    struct input_event event;
    int count = 0;

    /* 打开设备 */
    fd = open(dev_path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "错误: 无法打开设备 %s: %s\n", dev_path, strerror(errno));
        return -1;
    }

    printf("正在监控 input 事件\n");
    printf("设备: %s\n", dev_path);
    printf("按 Ctrl+C 退出\n");
    printf("----------------------------------------\n");

    /* 循环读取事件 */
    while (1) {
        ssize_t bytes = read(fd, &event, sizeof(event));

        if (bytes == sizeof(event)) {
            count++;

            if (event.type == EV_KEY) {
                const char *state;
                if (event.value == 0) {
                    state = "释放";
                } else if (event.value == 1) {
                    state = "按下";
                } else {
                    state = "重复";
                }

                printf("[%06d] 按键码 %d: %s (时间: %ld.%06ld)\n",
                       count, event.code, state,
                       event.time.tv_sec, event.time.tv_usec);
            } else if (event.type == EV_SYN) {
                /* Synchronization event - ignore */
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
    char dev_path[256] = {0};
    int opt;
    int list_only = 0;

    /* 解析命令行参数 */
    while ((opt = getopt(argc, argv, "d:lh")) != -1) {
        switch (opt) {
        case 'd':
            snprintf(dev_path, sizeof(dev_path), "%s", optarg);
            break;
        case 'l':
            list_only = 1;
            break;
        case 'h':
            print_usage(argv[0]);
            return 0;
        default:
            print_usage(argv[0]);
            return 1;
        }
    }

    /* 列出设备 */
    if (list_only) {
        return list_input_devices();
    }

    /* 如果没有指定设备，自动查找 */
    if (strlen(dev_path) == 0) {
        printf("正在查找 %s 设备...\n", EVENT_DEV_NAME);
        if (find_input_device(dev_path, sizeof(dev_path)) < 0) {
            fprintf(stderr, "错误: 找不到 %s 设备\n", EVENT_DEV_NAME);
            fprintf(stderr, "请尝试:\n");
            fprintf(stderr, "  1. 确保驱动已加载 (insmod)\n");
            fprintf(stderr, "  2. 使用 -l 列出所有设备\n");
            fprintf(stderr, "  3. 使用 -d 手动指定设备\n");
            return 1;
        }
        printf("找到设备: %s\n", dev_path);
    }

    /* 监控事件 */
    return monitor_input_events(dev_path);
}
