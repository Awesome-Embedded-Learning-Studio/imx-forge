# make-qemu-dtb.sh - QEMU 变体设备树编译脚本详解

## 脚本概述

`make-qemu-dtb.sh` 编译 QEMU 专用的板级设备树
`scripts/qemu_helper/imx6ull-aes-qemu.dts` → `out/qemu/imx6ull-aes-qemu.dtb`。
这份变体在 `imx6ull-aes.dtsi`（真机配置）基础上，**只 disable 在 QEMU
里会炸内核的节点**，其余板级配置（LED/beep/key、i2c 传感器、ecspi3、
usdhc、can1、sai2…）原样继承——一份设备树语义同时服务真机叙事和模拟器。

### 为什么需要变体

QEMU 的 i.MX6UL SoC 模型（`hw/arm/fsl-imx6ul.c`）实现了 UART/I2C/ECSPI/
USDHC/FEC/GPIO/GPT/EPIT/WDOG/SNVS；但 stock QEMU 8.2.x 对 mmdc/ocotp/qspi/
dcp/rngb/usbmisc/lcdif/pxp/csi/tsc 是**地址空洞**（连读 0 桩都没有）——
这些节点的驱动 probe 时 `readl` 直接触发 external abort，在
`of_platform_populate` 阶段杀死 PID 1 → kernel panic（表现是完全无串口
输出，因为死在 uart 完整驱动 probe 之前）。master/11.1+ 补了部分 stub
（Bin Meng 2026-08 系列），但仍非真模型。

### 变体里被 disable 的节点（12 个）

| 节点 | QEMU 8.2.x 状态 | master/11.1+ |
|---|---|---|
| memory-controller@21b0000 (mmdc) | 空洞 → abort | stub（Bin Meng 系列） |
| crypto@2280000 (dcp) | 空洞 | 空洞 |
| rng@2284000 (rngb) | 空洞 | 空洞 |
| spi@21e0000 (qspi) | 空洞 | stub |
| lcdif@21c8000 | 空洞 | **真模型（11.1+ 显示可用）** |
| pxp@21cc000 | 空洞 | 空洞 |
| csi@21c4000 | 空洞 | 空洞 |
| touchscreen@2040000 (tsc) | 空洞 | 空洞 |
| efuse@21bc000 (ocotp) | 空洞 | stub |
| usb@2184000/2184200/usbmisc | usbmisc 空洞 | stub |

> 注：升级到 QEMU ≥ 11.1 后，lcdif 可从 disable 列表移除（有真显示模型）；
> 其余节点即使有 stub，驱动也是读 0 软失败，disabled 与否不影响启动。

### 在开发工作流中的位置

QEMU 模拟链路三件套的第二步（见 `make-rootfs-img.sh.md`）。设备树源放在
`scripts/qemu_helper/`（不放内核树内），因为它不需要进内核构建系统；但它
`#include` 内核树里的 `imx6ull.dtsi` + `imx6ull-aes.dtsi`，**改共享 dtsi
时这份变体自动跟随**（重跑本脚本即可），符合设备树三处同步纪律。

## 用法示例

```bash
scripts/qemu_helper/make-qemu-dtb.sh
# → out/qemu/imx6ull-aes-qemu.dtb（run-qemu.sh 默认使用）
```

## 关键实现细节

- **cpp 预处理**：内核构建对 dts 先跑 `cpp -x assembler-with-cpp`（处理
  `#include`），dtc 本身不认 include；脚本镜像 `scripts/Makefile.lib` 的
  做法，`-I` 指到 `arch/arm/boot/dts/nxp/imx/`（v7.1 里 i.MX dtsi 的实际
  位置）
- **用内核自带 dtc**：`out/mainline/linux/scripts/dtc/dtc`（与内核构建同
  版本，避免系统 dtc 与内核 dtc 语法差异）；需要先跑过一次
  `build-mainline-linux.sh`
- **无 label 节点的引用**：mmdc 节点在 `imx6ul.dtsi` 里没有 label，用完整
  路径引用 `&{/soc/bus@2100000/memory-controller@21b0000}`
