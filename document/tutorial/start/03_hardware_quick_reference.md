---
title: 板子硬件接口速查表
---

# 板子硬件接口速查表

> 咱们用的板子是正点原子阿尔法 i.MX6ULL，本篇是它的**接口速查**：列出板载外设、用途与对应教程入口。引脚级配置见各驱动教程与 `imx6ull-aes.dtsi`。

## 板子概述

- **SoC**：i.MX6ULL（ARM Cortex-A7 单核，528 MHz）
- **内存**：512 MB DDR3
- **存储**：eMMC + SD 卡（视具体型号）
- **供电**：5V/2A DC

## 接口清单

| 接口 | 说明 | 用途 | 对应教程 |
|------|------|------|----------|
| Debug 串口 UART1 | 板载 USB 转串口，115200 8N1 | 看启动日志、命令行 | [串口工具](04_serial_tools_minicom.md) |
| 网口 | FEC1 + LAN8720A PHY | 网络启动/NFS/调试 | [kernel/06 网络启动](../kernel/06_wsl_network_boot.md) |
| USB OTG | USB OTG1 | UUU 烧录、设备模式 | [flash/10 uuu/ums](../flash/10_uuu_ums_emmc_flashing.md) |
| SD 卡 | USDHC1 | SD 卡启动 | [flash/09 SD 烧录](../flash/09_sd_card_flashing.md) |
| eMMC | USDHC2 | eMMC 启动/量产 | [flash/10](../flash/10_uuu_ums_emmc_flashing.md) |
| LCD | 7 寸 800×480 RGB | 显示 | [U-Boot 教程](../uboot/) |
| LED | GPIO1_IO03 | 点灯实验 | [driver/02 pinctrl/gpio](../driver/02_pinctrl_gpio/) |
| 蜂鸣器 | GPIO 控制 | beep 实验 | [driver/04 beep](../driver/04_beep_driver/) |
| 按键 | GPIO + 中断 | 按键实验 | [driver/05 按键](../driver/05_gpio_key_driver/) |
| I2C | AP3216C（光感/距离） | I2C 驱动 | [driver/08 i2c](../driver/08_i2c_ap3216c_driver/) |
| SPI | ICM20608（六轴） | SPI 驱动 | [driver/09 spi](../driver/09_spi_icm20608_driver/) |
| 触摸屏 | Goodix GT9147，I2C1 | 多点触控 | [driver/11 goodix](../driver/11_goodix_touchscreen_driver/) |
| 音频 | WM8960，SAI2 + I2C | 录放音 | [driver/12 wm8960](../driver/12_wm8960_audio_driver/) |
| RTC | SNVS | 实时钟 | [driver/10 rtc](../driver/10_rtc_snvs_driver/) |

::: tip 引脚去哪查
您查每个外设的具体引脚复用、电气配置，都在设备树源文件 `imx6ull-aes.dtsi`（NXP 轨）或主线对应 dtsi 里。修改流程见 [driver/01 板级 dts 修改](../driver/01_device_tree_base/09_board_dts_modification.md)。
:::

## 启动介质选择

板子通过拨码开关选择启动源，您动手前详见 [flash/04 启动流程与偏移](../flash/04_imx6ull_boot_flow_and_offsets.md)。

| 启动方式 | 说明 |
|----------|------|
| SD 卡启动 | 从 USDHC1 启动，开发期最常用 |
| eMMC 启动 | 从 USDHC2 启动，量产 |
| NFS 网络启动 | TFTP 拉内核/DTB + NFS rootfs，开发期调试神器 |

## 上电前检查

咱们上电前过一遍：确认电源 5V/2A，极性正确；
2. 确认拨码开关指向目标启动介质；
3. 确认串口线接好（TX/RX 交叉，见下一篇）；
4. SD/eMMC 已烧录镜像（见 [flash/](../flash/)）。

## 继续学习

- 串口工具配置：[串口工具使用（minicom）](04_serial_tools_minicom.md)
- 首次上电：[第一次上电与串口检查](05_first_boot_check.md)
- 存储与烧录：[flash/ 专栏](../flash/)
