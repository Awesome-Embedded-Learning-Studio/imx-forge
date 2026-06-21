/**
 * @file icm20608_app.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief ICM-20608 6-axis IMU test app — reads /dev/icm20608 in a loop
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
    printf("Usage: %s /dev/icm20608\n", app_name);
    printf("    - /dev/icm20608: char dev file created by the icm20608 driver\n");
    printf("Each read hands back {gx, gy, gz, ax, ay, az, temp} as seven signed ints\n");
    printf("(raw ADC). This app converts them to physical units using the ranges\n");
    printf("configured in the driver (gyro +-2000 deg/s, accel +-2g default).\n");
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

    /* gx, gy, gz, ax, ay, az, temp — order/type must line up with the driver. */
    signed int databuf[7];

    while (1) {
        const ssize_t bytes = read(dev_file_fd, databuf, sizeof(databuf));
        if (bytes == sizeof(databuf)) {
            const signed int gx = databuf[0], gy = databuf[1], gz = databuf[2];
            const signed int ax = databuf[3], ay = databuf[4], az = databuf[5];
            const signed int t = databuf[6];

            /* Divisors come straight from the chip's *actual* ranges. Gyro:
             * reginit writes GYRO_CONFIG=0x18 (+-2000 deg/s) and it sticks ->
             * 16.4 LSB/(deg/s). Accel: reginit writes ACCEL_CONFIG=0x18 (+-16g)
             * but on this board it does NOT take, so the chip stays at the
             * default +-2g -> 16384 LSB/g. If you ever get the +-16g write to
             * stick, flip these three back to 2048. */
            const float gx_act = (float)gx / 16.4f;
            const float gy_act = (float)gy / 16.4f;
            const float gz_act = (float)gz / 16.4f;
            const float ax_act = (float)ax / 16384.0f;
            const float ay_act = (float)ay / 16384.0f;
            const float az_act = (float)az / 16384.0f;
            const float t_act = ((float)t - 25.0f) / 326.8f + 25.0f;

            printf("gx=%.2f gy=%.2f gz=%.2f deg/s | ax=%.2f ay=%.2f az=%.2f g | t=%.2f C\n",
                   gx_act, gy_act, gz_act, ax_act, ay_act, az_act, t_act);
        } else if (bytes < 0) {
            printf("Failed to read the file: %s, code: %d\n", dev_file, errno);
            break;
        }
        usleep(100000); /* 100ms per sample */
    }

    close(dev_file_fd);
    return 0;
}
