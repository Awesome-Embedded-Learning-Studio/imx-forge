/**
 * @file icm20608_hw.h
 * @brief ICM-20608 hardware control interface (modern SPI API)
 *
 * The hardware layer owns everything that "talks to the chip": the bound
 * spi_device, register access via spi_write_then_read / spi_write, chip
 * bring-up and the latest gyro / accel / temp sample. The driver layer only
 * glues this onto a spi_driver and a character device.
 */

#pragma once

#include <linux/types.h>

struct spi_device;

/**
 * @brief ICM-20608 hardware context
 */
struct icm20608_hw_ctx {
    struct spi_device* spi;  /* spi_device we talk through */
    signed int gyro_x_adc, gyro_y_adc, gyro_z_adc;    /* gyroscope raw ADC */
    signed int accel_x_adc, accel_y_adc, accel_z_adc; /* accelerometer raw ADC */
    signed int temp_adc;                               /* temperature raw ADC */
};

/**
 * @brief Configure SPI mode, commit it and bring the chip out of reset
 * @param spi spi_device handed in by probe
 * @param ctx Context to initialize
 * @return 0 on success, negative errno on failure
 */
int icm20608_hw_init(struct spi_device* spi, struct icm20608_hw_ctx* ctx);

/**
 * @brief Deinitialize ICM-20608 hardware (nothing to free, devm-managed)
 * @param ctx ICM-20608 context
 */
void icm20608_hw_deinit(struct icm20608_hw_ctx* ctx);

/**
 * @brief Refresh ctx->gyro_* / accel_* / temp_adc with a fresh 14-byte burst
 * @param ctx ICM-20608 context
 */
void icm20608_hw_readdata(struct icm20608_hw_ctx* ctx);
