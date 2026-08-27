// SPDX-License-Identifier: GPL-2.0
/*
 * icm_app.c — read the real icm20608 through the 21-chapter teaching driver
 *
 * Pairs with the imxaes icm20608 SPI driver (driver/21_tutorial_icm20608_spi)
 * on the emulated AES board. One read() on /dev/icm20608 returns seven
 * signed ints: {gx, gy, gz, ax, ay, az, temp} raw ADC. This app prints
 * them raw AND converted (accel in g at +-16g, gyro in deg/s at +-2000,
 * temp in degrees C), twice, so you can watch the per-read sensor noise.
 *
 * QEMU-side injection ("rotate the board"):
 *   (qemu) qom-set /machine/soc/spi2/spi/child[0] accel-x 2048
 *
 * NOTE: the guest currently reads zeros through the driver — the imx_spi
 * controller model packs its 32-bit exchange words differently than the
 * kernel spi-imx driver unpacks them (the sample data IS visible on the
 * wire, see document/tutorial/emu/assets/spi-quirk-debug.log). The app
 * works unchanged once that quirk lands; on real hardware it works today.
 */

#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#define ACCEL_LSB_PER_G 2048.0f   /* +-16g range (driver sets 0x18) */
#define GYRO_LSB_PER_DPS 16.4f    /* +-2000 dps range (driver sets 0x18) */
#define TEMP_ZERO_OFFSET 25.0f
#define TEMP_LSB_PER_C   326.8f

static int read_once(int fd, int d[7])
{
    char *p = (char *)d;
    ssize_t got, n;

    n = 0;
    while (n < sizeof(int) * 7) {
        got = read(fd, p + n, sizeof(int) * 7 - n);
        if (got <= 0) {
            return -1;
        }
        n += got;
    }
    return 0;
}

int main(void)
{
    int fd;
    int d[7];
    int i;

    fd = open("/dev/icm20608", O_RDONLY);
    if (fd < 0) {
        perror("open /dev/icm20608 (insmod 21_tutorial_icm20608_spi_driver?)");
        return 1;
    }

    for (i = 0; i < 2; i++) {
        if (read_once(fd, d) < 0) {
            perror("read");
            close(fd);
            return 1;
        }
        printf("[%d] raw   gx=%5d gy=%5d gz=%5d ax=%5d ay=%5d az=%5d t=%5d\n",
               i, d[0], d[1], d[2], d[3], d[4], d[5], d[6]);
        printf("[%d] conv  ax=%6.2fg ay=%6.2fg az=%6.2fg  "
               "gx=%7.1f gy=%7.1f gz=%7.1f dps  T=%.1fC\n",
               i,
               d[3] / ACCEL_LSB_PER_G, d[4] / ACCEL_LSB_PER_G,
               d[5] / ACCEL_LSB_PER_G,
               d[0] / GYRO_LSB_PER_DPS, d[1] / GYRO_LSB_PER_DPS,
               d[2] / GYRO_LSB_PER_DPS,
               d[6] / TEMP_LSB_PER_C + TEMP_ZERO_OFFSET);
    }

    close(fd);
    return 0;
}
