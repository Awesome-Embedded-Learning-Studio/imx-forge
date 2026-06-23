# 22_tutorial_goodix_touchscreen

电容触摸（goodix）「分析型」教程配套。**本章不含可编译的内核驱动 `.ko`** —— 触摸驱动复用主线
`third_party/linux_mainline/drivers/input/touchscreen/goodix.c`，默认编进内核、开机自动 probe
（alpha 板 defconfig 已开 `CONFIG_TOUCHSCREEN_GOODIX=y`）。

## 配套产物

| 文件 | 位置 | 作用 |
|------|------|------|
| 板级设备树 | `driver/device_tree/alpha-board/22_tutorial_goodix_touchscreen/` | GT9147 节点（规范 `irq-gpios` 版） |

> 这个 `alpha-board/` 目录下**没有** `.c` 驱动、也没有内核模块 `Makefile`，因为本章不需要自己写驱动。
> 这是和 `20_tutorial_ap3216c_iic` / `21_tutorial_icm20608_spi` 那些「从零写」章节的本质区别，
> 详见教程 [06 节](../../../document/tutorial/driver/11_goodix_touchscreen_driver/06_build_and_test.md)。

## 设备树说明

alpha 板 `imx6ull-aes.dtsi` 的 `i2c2` 下已有一个 `gt9147@5d` 节点，但用的是 `interrupt-gpios`
属性；7.1 的 `goodix.c` 期望 `irq-gpios`（`devm_gpiod_get(dev, "irq")`）。配套 dts 把原节点删掉、
换成一个属性规范的版本（`interrupt-gpios` → `irq-gpios`），让 goodix 完整跑复位序列、稳稳锁定
`0x5d` 地址模式。其余属性（`compatible`/`reg`/`interrupts`/`reset-gpios`/电源/`pinctrl`）与 alpha
dtsi 一致。详见教程 [05 节](../../../document/tutorial/driver/11_goodix_touchscreen_driver/05_device_tree.md)。

## 启用与验证（详见教程 06 节）

```bash
# 1. 确认 goodix 已 probe（找 Goodix input 设备 + dmesg 看 ID 9147）
cat /proc/bus/input/devices | grep -i goodix
dmesg | grep -i goodix

# 2. evtest 看多点原始事件（ABS_MT_SLOT / TRACKING_ID / POSITION_X/Y）
evtest /dev/input/event0

# 3. tslib 移植 + 校准 + 多点测试（ts_calibrate / ts_test_mt）
#    （tslib 校准依赖 framebuffer，需 LCD 就绪；触摸驱动本身可先用 evtest 独立验证）
```

## alpha 板 GT9147 引脚

- **总线**：I2C2，从机地址 `0x5d`
- **中断 INT**：`GPIO1_IO09`（`interrupts = <9 0>` → `client->irq`，`request_irq` 用）
- **复位 RST**：`GPIO1_IO05`（`reset-gpios`，`goodix_reset` 操控）
- **电源**：`vdd-supply = <&reg_vddio>`（IO）、`avdd-supply = <&reg_avdd28>`（模拟 AVDD28）
