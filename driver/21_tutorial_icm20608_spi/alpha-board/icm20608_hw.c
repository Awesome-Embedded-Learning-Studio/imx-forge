/**
 * @file icm20608_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief ICM-20608 hardware control using the modern SPI API
 * @version 1.0
 * @date 2026-06-20
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "icm20608_hw.h"
#include "icm20608reg.h"
#include <linux/delay.h>
#include <linux/printk.h>
#include <linux/spi/spi.h>

/* Read N registers: bit7 of the address selects read. spi_write_then_read
 * strips the dummy byte for us, so buf is filled with pure payload — no
 * manual memmove like a hand-assembled spi_transfer would need. */
static int icm20608_read_regs(struct icm20608_hw_ctx* ctx, u8 reg, u8* buf, int len) {
    u8 reg_h = reg | 0x80; /* bit7 = 1 -> read */
    return spi_write_then_read(ctx->spi, &reg_h, 1, buf, len);
}

/* Write one register: bit7 of the address selects write. */
static int icm20608_write_reg(struct icm20608_hw_ctx* ctx, u8 reg, u8 val) {
    u8 buf[2];
    buf[0] = reg & ~0x80; /* bit7 = 0 -> write */
    buf[1] = val;
    return spi_write(ctx->spi, buf, 2);
}

static void icm20608_reginit(struct icm20608_hw_ctx* ctx) {
    icm20608_write_reg(ctx, ICM20608_PWR_MGMT_1, 0x80); /* reset */
    mdelay(50);
    icm20608_write_reg(ctx, ICM20608_PWR_MGMT_1, 0x01); /* wake up, PLL clock */
    icm20608_write_reg(ctx, ICM20608_SMPLRT_DIV, 0x00); /* no sample divider */
    icm20608_write_reg(ctx, ICM20608_GYRO_CONFIG, 0x18);  /* +-2000 deg/s */
    icm20608_write_reg(ctx, ICM20608_ACCEL_CONFIG, 0x18); /* +-16g */
}

int icm20608_hw_init(struct spi_device* spi, struct icm20608_hw_ctx* ctx) {
    if (!spi || !ctx) {
        pr_err("icm20608: invalid parameters\n");
        return -EINVAL;
    }

    ctx->spi = spi;
    ctx->gyro_x_adc = ctx->gyro_y_adc = ctx->gyro_z_adc = 0;
    ctx->accel_x_adc = ctx->accel_y_adc = ctx->accel_z_adc = 0;
    ctx->temp_adc = 0;

    /* Setting spi->mode only updates the software field; spi_setup() is what
     * programs mode / clock / word width into the controller hardware. */
    spi->mode = SPI_MODE_0; /* CPOL=0, CPHA=0 */
    spi_setup(spi);

    icm20608_reginit(ctx);

    dev_info(&spi->dev, "icm20608 hardware initialized\n");
    return 0;
}

void icm20608_hw_deinit(struct icm20608_hw_ctx* ctx) {
    if (!ctx) {
        return;
    }

    /* spi_device is owned by the bus core; nothing to free here. */
    dev_info(&ctx->spi->dev, "icm20608 hardware deinitialized\n");
}

void icm20608_hw_readdata(struct icm20608_hw_ctx* ctx) {
    unsigned char data[14];

    icm20608_read_regs(ctx, ICM20608_ACCEL_XOUT_H, data, 14);

    /* The cast to (signed short) is the load-bearing detail: the 16-bit
     * value must be read as signed so negatives sign-extend into the int. */
    ctx->accel_x_adc = (signed short)((data[0] << 8) | data[1]);
    ctx->accel_y_adc = (signed short)((data[2] << 8) | data[3]);
    ctx->accel_z_adc = (signed short)((data[4] << 8) | data[5]);
    ctx->temp_adc = (signed short)((data[6] << 8) | data[7]);
    ctx->gyro_x_adc = (signed short)((data[8] << 8) | data[9]);
    ctx->gyro_y_adc = (signed short)((data[10] << 8) | data[11]);
    ctx->gyro_z_adc = (signed short)((data[12] << 8) | data[13]);
}
