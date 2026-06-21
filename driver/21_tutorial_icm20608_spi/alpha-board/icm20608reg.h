/**
 * @file icm20608reg.h
 * @brief ICM-20608 register address map (TDK InvenSense 6-axis IMU)
 *
 * Data registers start at 0x3B and run contiguously for 14 bytes:
 * ax/ay/az/temp/gx/gy/gz, so a single burst read hands back every axis.
 *
 * SPI convention: register address bit7 selects direction — 0 for write,
 * 1 for read.
 */

#pragma once

/* clang-format off */

#define ICM20608_SMPLRT_DIV     0x19  /* Sample rate divider     */
#define ICM20608_GYRO_CONFIG    0x1B  /* Gyroscope configuration */
#define ICM20608_ACCEL_CONFIG   0x1C  /* Accelerometer config    */
#define ICM20608_ACCEL_CONFIG2  0x1D  /* Accelerometer config 2  */
#define ICM20608_PWR_MGMT_1     0x6B  /* Power management 1      */
#define ICM20608_PWR_MGMT_2     0x6C  /* Power management 2      */
#define ICM20608_WHO_AM_I       0x75  /* Who am I                */

/* Burst-read start: 14 bytes = ax/ay/az/temp/gx/gy/gz (H then L each). */
#define ICM20608_ACCEL_XOUT_H   0x3B

/* clang-format on */
