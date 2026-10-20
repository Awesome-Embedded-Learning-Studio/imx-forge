---
title: Goodix 触摸屏 I2C 地址错（0x5d vs 0x14）
---

# 2026-06-29 Goodix GT9147 触摸屏 -6 ENXIO：地址写成 0x5d，实测在 0x14

netboot 启动 `imx6ull-aes.dtb` 时，Goodix 触摸屏驱动 probe 失败，串口日志一片
`Error ... -6`。这篇记一个**反复会踩**的坑：Goodix 的 I2C 从地址不是固定的，而
设备树（和很多教程）默认写 `0x5d`，但本板实测在 `0x14`。只要换板子、换 INT/RESET
上电时序，地址就可能落到另一个值——所以把**排查方法**记下来比记答案更值。

## Context

- 触摸芯片：正点原子 i.MX6ULL AES 板上的 Goodix **GT9147**，挂在 **i2c-1**。
- 驱动：mainline `drivers/input/touchscreen/goodix.c`（分析型章节路线，拆现成驱动
  不重写，见 [触摸章节](../tutorial/kernel/10_touch_gt9xx.md)）。
- 设备树：netboot base 镜像 `imx6ull-aes.dtb` 由 `linux/imx6ull-aes.dts`
  `#include "imx6ull-aes.dtsi"` 编出，goodix 节点就在这个**共享 dtsi** 里。

## Symptom

内核起来后，触摸驱动连试两次读寄存器都失败，然后放弃 probe：

```text
[   12.006241] Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6
[   12.035073] Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6
[   12.064510] Goodix-TS 1-005d: I2C communication failure: -6
```

之后 `/dev/input/eventX` 不出现，触摸不可用。**注意：probe 失败不是 fatal**，
后面 DHCP、继续启动都正常——别把它和「起不来」混淆。

## Key Insight —— `-6` 是「设备没应答」，先别怪驱动

逐字段拆这一行 `Goodix-TS 1-005d: Error reading 1 bytes from 0x8140: -6`：

- `1-005d` = Linux i2c **bus 1**、从**地址 0x5d**（这是设备树 `reg` 给的）。
- `0x8140` = Goodix 的 **Product ID 寄存器**（`GT9147_PRODUCT_ID`）。驱动 probe 时
  第一步就是读它来辨认芯片型号。
- **`-6 = -ENXIO`** = I2C 传输层最经典的「**No ACK**」：master 在 0x5d 发起读，
  总线上**没有任何设备在那个地址应答**。

`-ENXIO` 本身不能区分地址错误、供电缺失或复位未释放。先核对驱动使用的地址、
供电与 RESET/INT 时序，再按需扫描总线。尤其不能仅凭扫描到 0x14，就断定只改 `reg` 足够。

## Investigation

### Step 1 —— `i2cdetect` 直接看芯片在哪个地址

板子进 shell 后（这个 probe 是内核侧、boot 早期就发生，跟 rootfs/init 无关，
哪怕 NFS root 还没修好也能验）：

```bash
i2cdetect -y 1
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- --
# 10: -- -- -- -- 14 -- -- -- -- -- -- -- -- -- -- --
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# ...（其余全 --）
```

整条 i2c-1 上**只有 0x14 那一格有应答**。同总线的 `ov5640@3c` 是
`status="disabled"`，所以 0x14 必然就是 GT9147，没有歧义。**芯片在 0x14，
驱动却去 0x5d 找** → -6。

### Step 2 —— 反编译正在 boot 的 dtb，确认 `reg`

```bash
dtc -I dtb -O dts /home/charliechen/tftp/imx6ull-aes.dtb 2>/dev/null | grep -A3 'gt9147@'
# 				gt9147@5d {
# 					compatible = "goodix,gt9147\0goodix,gt9xx";
# 					reg = <0x5d>;
```

果然 `reg = <0x5d>`。源在 `driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi` 的 goodix 节点。

### Step 3 —— 为什么是 0x14 不是 0x5d

Goodix GT9xx 系列的 **7-bit I2C 从地址不是固定的**，由 **RESET 上升沿那一刻 INT
引脚的电平**决定：

| INT @ RESET 上升沿 | 7-bit 地址 | 8-bit 写/读 |
|---|---|---|
| **高** | **`0x14`** | `0x28 / 0x29` |
| 低 | `0x5d` | `0xBA / 0xBB` |

主线 `goodix_reset_no_int_sync()` 会先拉低 RESET，再按 `client->addr == 0x14`
驱动 INT，最后拉高 RESET。因此 RESET 和 INT 的 GPIO 描述都用
`GPIO_ACTIVE_HIGH`，使逻辑值对应实际电平；这里不能按“复位低有效”直接写
`GPIO_ACTIVE_LOW`，否则驱动序列被反相。此前表格写反，已于 2026-10-20 更正。

依据：[主线 Goodix 驱动](https://github.com/torvalds/linux/blob/master/drivers/input/touchscreen/goodix.c)
和 [设备树绑定](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/input/touchscreen/goodix.yaml)。

## Root Cause

设备树 goodix 节点 `reg = <0x5d>` 与芯片实际地址 `0x14` 不符 → 驱动在 0x5d 读
Product ID 寄存器（0x8140）得不到 ACK → `-ENXIO` → probe 失败。

## 当前修复与构建（2026-10-20）

本次完整 SD 启动排查、regulator 延迟探测修复及真板/QEMU 验证边界，见
[2026-10-20 启动修复记录](2026-10-20-uboot-shared-mdio-handoff.md)。

板级设备树的唯一维护源是
`driver/device_tree/alpha-board/linux/imx6ull-aes.dtsi`；
`scripts/build_helper/build-linux.sh` 会将它复制进内核树，并由同目录的
`imx6ull_mainline_defconfig.template` 生成 defconfig。旧版 Linux patch 三处
同步的流程已停用。

当前节点使用 `touchscreen@14` / `reg = <0x14>`，并同时修正：

- RESET GPIO1_IO05、INT GPIO1_IO09 都用 `GPIO_ACTIVE_HIGH`，匹配主线复位序列。
- 电源属性使用区分大小写的 `VDDIO-supply`、`AVDD28-supply`。
- 移除绑定不支持的 `goodix,gt9xx` 备用兼容串。
- SD 固定电源没有 GPIO1_IO09 控制，避免和触摸中断争用。
- 模板启用 `CONFIG_REGULATOR=y`，使固定电源驱动及其供应关系实际生效。

从项目根目录同步并增量重编：

```bash
scripts/build_helper/build-linux.sh --fast-build
```

该命令同时重编内核和 DTB。原先内核没有 regulator 支持，本次不能仅替换 DTB。
不要将 `third_party/linux_mainline` 中的构建副本当作长期维护源。

真板重启后验证：

```sh
dmesg | grep -i goodix
cat /proc/bus/input/devices
cat /proc/interrupts
```

期望出现 `Goodix-TS 1-0014: ID ...`、`Goodix Capacitive TouchScreen` 输入设备。
实际触摸时还需确认对应 GPIO 中断计数增长且事件节点产生数据。
I2C 设备已绑定时，扫描结果可能显示 `UU`；驱动绑定、芯片识别和触摸事件
比单独扫描更能说明问题。新镜像的实际触摸仍需真板复测。

## Verified (2026-06-29)

`reg` 改为 `0x14`、重编部署、重启板子后，触摸驱动正常 probe，`/dev/input/eventX`
出现，`Goodix-TS 1-005d ... -6` 消失。修复端到端确认。

> 附注：本次部署的 dtb 来自「只 apply 了触摸 patch」的内核树，比之前的 tftp dtb
> 少了 `icm20608@0`（SPI 加速度计）和 `sim@021b4000` 两个节点。纯测触摸无影响；
> 需要那些节点的话，把对应章节的 patch 也 apply 进树再重编。回退用
> `imx6ull-aes-before-goodix-fix.dtb`。

## See Also

- [2026-06-08 WSL2 NFS Rootfs 排查记录](2026-06-08-wsl2-nfsroot-ganesha-troubleshoot.md) —— 另一个「内核侧症状、根因在 host/配置」的排查范例。
- [设备树基础](../tutorial/uboot/05_device_tree_basics.md) —— dts/dtsi/dtb 的关系与编译。
- [触摸章节（mainline goodix 分析）](../tutorial/kernel/10_touch_gt9xx.md) —— GT9147 驱动分析型章节。
