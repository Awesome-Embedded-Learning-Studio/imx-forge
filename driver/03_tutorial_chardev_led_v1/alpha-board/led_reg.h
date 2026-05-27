#pragma once
#include <linux/kernel.h>

// Reference: document/tutorial/third_party/imx6ull/IMX6ULL_Reference_Manual.pdf

/* ============================================================================
 * i.MX6ULL Memory-Mapped Register Addresses
 * ============================================================================ */

/* CCM (Clock Control Module) CCGR1 - Clock Gating Register 1
 * Address: 0x020C406C
 * Purpose: Enable/disable GPIO1 peripheral clock (must be enabled for GPIO to work)
 * Reference: Reference Manual Chapter 18 (Clock Control Module)
 * Page: Page 700
 */
static const u32 kCCM_CCGR1_BASE = 0X020C406C;

/* IOMUXC SW_MUX_CTL - Software Mux Control Register
 * Address: 0x020E0068
 * Purpose: Configure GPIO1_IO03 pin function mode, set to ALT5 (value=5) for GPIO
 * Why bit 3: GPIO1_IO03 → "03" means pin #3 → operates on bit 3 in registers
 * Reference: Reference Manual Chapter 32 (IOMUX Controller)
 * Page: Page 1571
 */
static const u32 kSW_MUX_GPIO1_IO03_BASE = 0X020E0068;

/* IOMUXC SW_PAD_CTL - Pad Configuration Register
 * Address: 0x020E02F4
 * Purpose: Configure pin electrical properties (drive strength, slew rate, pull-up/down)
 * Page: Page 1793
 */
static const u32 kSW_PAD_GPIO1_IO03_BASE = 0X020E02F4;

/* GPIO1 DR (Data Register) - Data Register
 * Address: 0x0209C000
 * Purpose: Read/write GPIO pin output levels
 * bit 3: Controls GPIO1_IO03 output state (0=low/LED on, 1=high/LED off)
 * Why bit 3: Pin name IO03 = pin #3 (counting from 0)
 * Page: 1357, At Chapter 28
 */
static const u32 kGPIO1_DR_BASE = 0X0209C000;

/* GPIO1 GDIR (Direction Register) - Direction Register
 * Address: 0x0209C004
 * Purpose: Configure GPIO pin direction (input/output)
 * bit 3: 0=input mode, 1=output mode
 * Why bit 3: Corresponds to GPIO1_IO03 pin
 * Page: 1357, At Chapter 28
 */
static const u32 kGPIO1_GDIR_BASE = 0X0209C004;