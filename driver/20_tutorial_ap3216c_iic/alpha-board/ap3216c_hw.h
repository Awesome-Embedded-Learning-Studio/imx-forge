/**
 * @file ap3216c_hw.h
 * @brief AP3216C hardware control interface (modern I2C API)
 *
 * The hardware layer owns everything that "talks to the chip": the bound
 * i2c_client, register access via i2c_smbus_*, chip bring-up and the latest
 * IR / ALS / PS sample. The driver layer only glues this onto an i2c_driver
 * and a character device.
 */

#pragma once

#include <linux/types.h>

struct i2c_client;

/**
 * @brief AP3216C hardware context
 */
struct ap3216c_hw_ctx {
    struct i2c_client* client;  /* i2c_client we talk through */
    unsigned short ir;          /* IR  sample                 */
    unsigned short als;         /* ALS sample                 */
    unsigned short ps;          /* PS  sample                 */
};

/**
 * @brief Bind the client and bring the chip into ALS+PS+IR mode
 * @param client i2c_client handed in by probe
 * @param ctx Context to initialize
 * @return 0 on success, negative errno on failure
 */
int ap3216c_hw_init(struct i2c_client* client, struct ap3216c_hw_ctx* ctx);

/**
 * @brief Deinitialize AP3216C hardware (nothing to free, devm-managed)
 * @param ctx AP3216C context
 */
void ap3216c_hw_deinit(struct ap3216c_hw_ctx* ctx);

/**
 * @brief Refresh ctx->ir / als / ps with a fresh sample from the chip
 * @param ctx AP3216C context
 */
void ap3216c_hw_readdata(struct ap3216c_hw_ctx* ctx);
