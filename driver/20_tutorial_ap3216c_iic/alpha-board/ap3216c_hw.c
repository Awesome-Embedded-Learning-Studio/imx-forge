/**
 * @file ap3216c_hw.c
 * @author Charliechen114514 (chengh1922@mails.jlu.edu.cn)
 * @brief AP3216C hardware control using the modern I2C (SMBus) API
 * @version 1.0
 * @date 2026-06-20
 *
 * @copyright Copyright (c) 2026
 *
 */

#include "ap3216c_hw.h"
#include "ap3216creg.h"
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/printk.h>

/* Read one register. i2c_smbus_read_byte_data returns the byte value or a
 * negative errno; it is internally the same "write address then read data"
 * two-step transfer you would hand-assemble with i2c_transfer. */
static int ap3216c_read_reg(struct ap3216c_hw_ctx* ctx, u8 reg) {
    return i2c_smbus_read_byte_data(ctx->client, reg);
}

/* Write one register. */
static int ap3216c_write_reg(struct ap3216c_hw_ctx* ctx, u8 reg, u8 val) {
    return i2c_smbus_write_byte_data(ctx->client, reg, val);
}

int ap3216c_hw_init(struct i2c_client* client, struct ap3216c_hw_ctx* ctx) {
    if (!client || !ctx) {
        pr_err("ap3216c: invalid parameters\n");
        return -EINVAL;
    }

    ctx->client = client;
    ctx->ir = 0;
    ctx->als = 0;
    ctx->ps = 0;

    /* Power-on ritual: soft reset, let it settle, then enable ALS+PS+IR. */
    ap3216c_write_reg(ctx, AP3216C_SYSTEMCONG, 0x04); /* 0x04 = soft reset */
    msleep(10);
    ap3216c_write_reg(ctx, AP3216C_SYSTEMCONG, 0x03); /* 0x03 = ALS+PS+IR on */

    dev_info(&client->dev, "ap3216c hardware initialized\n");
    return 0;
}

void ap3216c_hw_deinit(struct ap3216c_hw_ctx* ctx) {
    if (!ctx) {
        return;
    }

    /* Registers / client are devm-managed or owned by the bus core. */
    dev_info(&ctx->client->dev, "ap3216c hardware deinitialized\n");
}

void ap3216c_hw_readdata(struct ap3216c_hw_ctx* ctx) {
    u8 i;
    u8 buf[6];

    /* 0x0A~0x0F contiguous: IR_L/IR_H/ALS_L/ALS_H/PS_L/PS_H */
    for (i = 0; i < 6; i++) {
        buf[i] = (u8)ap3216c_read_reg(ctx, AP3216C_IRDATALOW + i);
    }

    /* IR: 10-bit, bit7 of the low byte flags an invalid (overflow) sample. */
    if (buf[0] & 0x80) {
        ctx->ir = 0;
    } else {
        ctx->ir = ((unsigned short)buf[1] << 2) | (buf[0] & 0x03);
    }

    /* ALS: 16-bit. */
    ctx->als = ((unsigned short)buf[3] << 8) | buf[2];

    /* PS: bit6 of the low byte flags an invalid sample. */
    if (buf[4] & 0x40) {
        ctx->ps = 0;
    } else {
        ctx->ps = ((unsigned short)(buf[5] & 0x3F) << 4) | (buf[4] & 0x0F);
    }
}
