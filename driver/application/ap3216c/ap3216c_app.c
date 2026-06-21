/**
 * @file ap3216c_app.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief AP3216C IR/ALS/PS sensor test app — reads /dev/ap3216c in a loop
 * @note Clangd might dumped, build once to override the kernel compile!
 * @version 0.1
 * @date 2026-06-20
 *
 * @copyright Copyright (c) 2026
 *
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

void print_usage(const char* app_name) {
    printf("Usage: %s /dev/ap3216c\n", app_name);
    printf("    - /dev/ap3216c: char dev file created by the ap3216c driver\n");
    printf("Each read hands back {ir, als, ps} as three unsigned shorts.\n");
    printf("@note: make sure the driver is loaded and the dev node exists!\n");
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char* dev_file = argv[1];
    const int dev_file_fd = open(dev_file, O_RDWR);
    if (dev_file_fd < 0) {
        printf("Failed to open the file: %s, code: %d\n", dev_file, errno);
        return 1;
    }

    /* ir, als, ps — order/type must line up with the driver's copy_to_user. */
    unsigned short databuf[3];

    while (1) {
        const ssize_t bytes = read(dev_file_fd, databuf, sizeof(databuf));
        if (bytes == sizeof(databuf)) {
            printf("ir = %d, als = %d, ps = %d\n", databuf[0], databuf[1], databuf[2]);
        } else if (bytes < 0) {
            printf("Failed to read the file: %s, code: %d\n", dev_file, errno);
            break;
        }
        usleep(200000); /* 200ms per sample */
    }

    close(dev_file_fd);
    return 0;
}
