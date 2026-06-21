/**
 * @file ap3216creg.h
 * @brief AP3216C register address map (Lite-On IR / ALS / PS sensor)
 *
 * IR / ALS / PS data registers live at contiguous addresses 0x0A~0x0F,
 * so a single burst read of six bytes hands back all three channels.
 */

#pragma once

/* clang-format off */

#define AP3216C_SYSTEMCONG   0x00  /* System configuration */
#define AP3216C_INTSTATUS    0x01  /* Interrupt status      */
#define AP3216C_INTCLEAR     0x02  /* Interrupt clear       */
#define AP3216C_IRDATALOW    0x0A  /* IR  data low byte     */
#define AP3216C_IRDATAHIGH   0x0B  /* IR  data high byte    */
#define AP3216C_ALSDATALOW   0x0C  /* ALS data low byte     */
#define AP3216C_ALSDATAHIGH  0x0D  /* ALS data high byte    */
#define AP3216C_PSDATALOW    0x0E  /* PS  data low byte     */
#define AP3216C_PSDATAHIGH   0x0F  /* PS  data high byte    */

/* clang-format on */
